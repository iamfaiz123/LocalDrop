import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../platform/native_bridge.dart';
import '../services/api_client.dart';
import '../services/download_manager.dart';
import '../services/engine_service.dart';
import '../services/preferences.dart';
import '../services/realtime_service.dart';
import '../services/upload_manager.dart';
import '../utils/format.dart';
import 'gallery_controller.dart';

enum SessionRole { none, host, participant }

enum SessionPhase { idle, starting, pending, active, ended, removed }

enum StartStepState { pending, running, done, warning, failed }

/// A session this device still belongs to but is not attached to right now
/// (host server could not be restarted, or the host is unreachable).
/// While set, creating or joining another session is not allowed.
class LockedSession {
  final SessionRole role;
  final String name;
  final String reason;
  const LockedSession(this.role, this.name, this.reason);
}

class StartStep {
  final String label;
  StartStepState state = StartStepState.pending;
  String? detail;
  StartStep(this.label);
}

/// Application-level session state machine for both roles.
///
/// Host:        createSession → engine (Rust) starts → API on 127.0.0.1.
/// Participant: probe(address) → join(name, PIN) → API on the host's LAN IP.
/// Both then share the same gallery/upload/download code paths.
class SessionController extends ChangeNotifier {
  final EngineService engine;
  final Preferences prefs;
  final NativeBridge native;
  final Future<String> Function() dataDir;
  final GalleryController gallery;
  final UploadManager uploads;
  final DownloadManager downloads;

  SessionController({
    required this.engine,
    required this.prefs,
    required this.dataDir,
    required this.gallery,
    required this.uploads,
    required this.downloads,
    this.native = const NativeBridge(),
  });

  SessionRole role = SessionRole.none;
  SessionPhase phase = SessionPhase.idle;
  ApiClient? api;
  RealtimeService? _realtime;
  StreamSubscription<ServerEvent>? _eventSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  ConnectionStatus connection = ConnectionStatus.closed;

  SessionInfo? session;
  Participant? me;
  HostSession? host;
  List<Participant> participants = const [];
  SessionStats? stats;
  String? endedMessage;
  bool storageWarning = false;

  // Host network state (updates live when interfaces change).
  List<NetworkInterfaceInfo> interfaces = const [];
  List<String> hostUrls = const [];
  String? joinUrl;
  bool networkOk = false;

  List<StartStep> steps = [];
  LockedSession? locked;

  Timer? _pendingPoll;
  Timer? _peopleDebounce;
  final _events = StreamController<ServerEvent>.broadcast();
  Stream<ServerEvent> get events => _events.stream;

  bool get isHost => role == SessionRole.host;

  /// True while this device belongs to a session (attached or not). Only one
  /// session at a time: Create/Join are unavailable until it is ended (host)
  /// or left (participant).
  bool get hasSession =>
      locked != null || phase == SessionPhase.starting || phase == SessionPhase.pending || phase == SessionPhase.active;
  bool get inSession => phase == SessionPhase.active;
  int get activeMembers => participants.where((p) => p.isActive).length;
  List<Participant> get pendingRequests => participants.where((p) => p.isPending).toList();

  // ------------------------------------------------------------------ startup

  /// Restores state when the app UI starts. Returns true if attached to a
  /// session (the UI then opens it directly).
  ///
  /// 1. Host server still running in this process (app was closed, the
  ///    background service kept it alive) → re-attach.
  /// 2. Host session recorded but the server is not running (process was
  ///    killed) → restart it automatically with the same PIN and data.
  /// 3. Participant session recorded → reconnect to the host.
  /// If 2/3 fail, the session stays [locked] until the user ends/leaves it.
  Future<bool> restore() async {
    locked = null;
    final recordedHost = await prefs.hostSessionId();
    final recordedGuest = await prefs.participantSession();
    try {
      final st = await engine.status();
      final running = st.session;
      // Only re-attach to a server this device is recorded as hosting.
      if (st.running && !st.ended && running != null && (recordedHost == running.sessionId || recordedGuest == null)) {
        await _attachHost(running);
        return true;
      }
    } on Exception catch (e) {
      debugPrint('LocalDrop: engine status unavailable: $e');
    }

    final name = await prefs.activeSessionName() ?? 'your session';
    final hostId = recordedHost;
    if (hostId != null) {
      try {
        final stored = await engine.storedSessions(await dataDir());
        final s = stored.where((x) => x.id == hostId).firstOrNull;
        if (s == null || s.ended) {
          await _clearMembership();
          notifyListeners();
          return false;
        }
      } on EngineException {
        // fall through and try to start it anyway
      }
      if (await createSession(sessionName: name, hostName: '', resumeId: hostId)) return true;
      final why = steps.where((x) => x.state == StartStepState.failed).map((x) => x.detail).firstOrNull;
      locked = LockedSession(SessionRole.host, name, 'Your session could not be restarted${why == null ? '' : ': $why'}');
      notifyListeners();
      return false;
    }

    final p = recordedGuest;
    if (p != null) {
      final client = ApiClient(Uri.parse(p.base), token: p.token);
      try {
        final (meP, info) = await client.me();
        if (info.id == p.sessionId && meP.isActive) {
          await _enterParticipant(client, meP, info);
          return true;
        }
        if (info.id == p.sessionId && meP.isPending) {
          role = SessionRole.participant;
          api = client;
          me = meP;
          session = info;
          phase = SessionPhase.pending;
          _pollApproval(client);
          notifyListeners();
          return false;
        }
        client.close();
        await _clearMembership();
      } on ApiException catch (e) {
        client.close();
        if (e.isNetwork) {
          locked = LockedSession(SessionRole.participant, name,
              'Can’t reach the host right now. Reconnect to the host’s hotspot or Wi-Fi and tap Reconnect.');
        } else {
          await _clearMembership();
        }
      }
    }
    notifyListeners();
    return false;
  }

  Future<void> _clearMembership() async {
    await prefs.clearParticipantSession();
    await prefs.setHostSessionId(null);
    await prefs.setActiveSessionName(null);
    locked = null;
  }

  /// Ends a host session that could not be restarted. Tries to restart it so
  /// participants are told; the media stays on the device either way.
  Future<void> endLockedSession() async {
    final l = locked;
    if (l == null) return;
    if (l.role == SessionRole.host) {
      final id = await prefs.hostSessionId();
      if (id != null && await createSession(sessionName: l.name, hostName: '', resumeId: id)) {
        await endSession(deleteMedia: false);
        acknowledgeEnd();
        return;
      }
      await native.stopHostingService();
    } else {
      final p = await prefs.participantSession();
      if (p != null) {
        final client = ApiClient(Uri.parse(p.base), token: p.token, timeout: const Duration(seconds: 4));
        try {
          await client.leave();
        } on ApiException {
          // host unreachable: leave locally
        } finally {
          client.close();
        }
      }
    }
    await _clearMembership();
    phase = SessionPhase.idle;
    role = SessionRole.none;
    notifyListeners();
  }

  Future<List<NetworkInterfaceInfo>> checkNetwork() async {
    try {
      interfaces = await engine.interfaces();
    } on EngineException {
      interfaces = const [];
    }
    networkOk = interfaces.any((i) => i.usable);
    notifyListeners();
    return interfaces;
  }

  // ------------------------------------------------------------------ host

  /// Creates (or resumes) a hosted session. Progress is reported in [steps].
  Future<bool> createSession({
    required String sessionName,
    required String hostName,
    bool requireApproval = false,
    String? resumeId,
  }) async {
    if (resumeId == null && hasSession) {
      steps = [StartStep('Checking network')..state = StartStepState.failed
        ..detail = 'You are already in a session. End or leave it before creating a new one.'];
      notifyListeners();
      return false;
    }
    steps = [StartStep('Checking network'), StartStep('Starting local server'), StartStep('Preparing gallery')];
    phase = SessionPhase.starting;
    role = SessionRole.host;
    notifyListeners();

    Future<void> run(int i, Future<void> Function(StartStep s) body) async {
      steps[i].state = StartStepState.running;
      notifyListeners();
      await body(steps[i]);
      if (steps[i].state == StartStepState.running) steps[i].state = StartStepState.done;
      notifyListeners();
    }

    var current = 0;
    try {
      await run(current, (s) async {
        await checkNetwork();
        if (!networkOk) {
          s.state = StartStepState.warning;
          s.detail = 'No hotspot or Wi-Fi network found. Turn on your hotspot — the join address will appear automatically.';
        } else {
          final best = interfaces.firstWhere((i) => i.usable);
          s.detail = '${best.kind == 'hotspot' ? 'Hotspot' : 'Wi-Fi'} · ${best.ip}';
        }
      });
      current = 1;
      await run(current, (s) async {
        host = await engine.start(EngineConfig(
          dataDir: await dataDir(),
          sessionName: sessionName,
          hostName: hostName,
          requireApproval: requireApproval,
          resumeSessionId: resumeId,
        ));
        s.detail = 'Listening on port ${host!.port}';
      });
      current = 2;
      await run(current, (s) async {
        if (hostName.isNotEmpty) await prefs.setLastName(hostName);
        await _attachHost(host!);
      });
      return true;
    } catch (e) {
      steps[current].state = StartStepState.failed;
      steps[current].detail = e.toString();
      phase = SessionPhase.idle;
      role = SessionRole.none;
      if (host != null && current == 2) {
        await engine.stop();
        host = null;
      }
      notifyListeners();
      return false;
    }
  }

  /// Connects the UI to the running host server and keeps it alive in the
  /// background until the host ends the session.
  Future<void> _attachHost(HostSession h) async {
    host = h;
    role = SessionRole.host;
    final client = ApiClient(Uri.parse(h.localUrl), token: h.hostToken);
    final (meP, info) = await client.me();
    hostUrls = h.urls;
    joinUrl = h.joinUrl;
    networkOk = h.networkOk;
    interfaces = h.addresses;
    locked = null;
    await prefs.setHostSessionId(h.sessionId);
    await prefs.setActiveSessionName(info.name);
    await _enterSession(client, meP, info);
    downloads.attach(client, localPath: (m) => '${h.sessionDir}/media/${m.id}.${m.ext}');
    final resume = jsonEncode({'data_dir': await dataDir(), 'resume_session_id': h.sessionId});
    await native.startHostingService(info.name, resumeConfig: resume);
  }

  // ------------------------------------------------------------------ participant

  /// Checks that a host is reachable and returns its public session info.
  Future<(Uri, SessionInfo)> probe(String address) async {
    final parsed = parseServerAddress(address);
    if (parsed == null) {
      throw const ApiException(0, 'bad_address', 'Enter an address like 192.168.1.5:8080 or scan the QR code');
    }
    final client = ApiClient(parsed.base, timeout: const Duration(seconds: 8));
    try {
      final info = await client.sessionInfo();
      if (info.ended) throw const ApiException(410, 'session_ended', 'This session has ended');
      return (parsed.base, info);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        throw ApiException(0, e.code,
            'Can’t reach ${parsed.base.host}:${parsed.base.port}. Make sure you are connected to the host’s hotspot or Wi-Fi. '
            'Some hotspots block devices from talking to each other — if so, ask the host to switch networks.');
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Joins a session. Returns the participant status (`active` / `pending`).
  Future<String> join(Uri base, {required String name, required String pin}) async {
    if (hasSession) {
      throw const ApiException(0, 'already_in_session', 'You are already in a session. Leave it before joining another one.');
    }
    final client = ApiClient(base);
    try {
      final (meP, info) = await client.join(name: name, pin: pin, deviceId: await prefs.deviceId());
      await prefs.setLastName(name);
      await prefs.setParticipantSession(base.toString(), client.token!, info.id);
      await prefs.setActiveSessionName(info.name);
      role = SessionRole.participant;
      if (meP.isPending) {
        api = client;
        me = meP;
        session = info;
        phase = SessionPhase.pending;
        notifyListeners();
        _pollApproval(client);
      } else {
        await _enterParticipant(client, meP, info);
      }
      return meP.status;
    } catch (_) {
      if (phase != SessionPhase.pending && phase != SessionPhase.active) client.close();
      rethrow;
    }
  }

  void _pollApproval(ApiClient client) {
    _pendingPoll?.cancel();
    _pendingPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final (meP, info) = await client.me();
        if (meP.isActive) {
          _pendingPoll?.cancel();
          await _enterParticipant(client, meP, info);
        } else if (!meP.isPending) {
          _pendingPoll?.cancel();
          _finish(SessionPhase.removed, 'The host did not let you in.');
        }
      } on ApiException catch (e) {
        if (e.isAuth || e.sessionEnded) {
          _pendingPoll?.cancel();
          _finish(e.sessionEnded ? SessionPhase.ended : SessionPhase.removed,
              e.sessionEnded ? 'The host ended this session.' : 'The host did not let you in.');
        }
      }
    });
  }

  Future<void> cancelPending() async {
    _pendingPoll?.cancel();
    try {
      await api?.leave();
    } on ApiException {
      // already gone
    }
    await _teardown();
    await _clearMembership();
    phase = SessionPhase.idle;
    role = SessionRole.none;
    notifyListeners();
  }

  Future<void> _enterParticipant(ApiClient client, Participant meP, SessionInfo info) async {
    role = SessionRole.participant;
    await _enterSession(client, meP, info);
    downloads.attach(client);
  }

  Future<void> _enterSession(ApiClient client, Participant meP, SessionInfo info) async {
    api = client;
    me = meP;
    session = info;
    endedMessage = null;
    phase = SessionPhase.active;
    _realtime = RealtimeService(client);
    _eventSub = _realtime!.events.listen(_onEvent);
    _statusSub = _realtime!.statusStream.listen((s) {
      final wasDown = connection != ConnectionStatus.connected;
      connection = s;
      if (s == ConnectionStatus.connected && wasDown) {
        uploads.resumeAll();
        downloads.resumeAll();
      }
      notifyListeners();
    });
    unawaited(_realtime!.connect());
    gallery.attach(client, meId: meP.id, isHost: meP.isHost);
    await uploads.attach(client, info.id);
    unawaited(refreshParticipants());
    notifyListeners();
  }

  // ------------------------------------------------------------------ actions

  Future<void> refreshParticipants() async {
    final client = api;
    if (client == null) return;
    try {
      participants = await client.participants();
      notifyListeners();
    } on ApiException catch (e) {
      _handleApiError(e);
    }
  }

  Future<void> refreshStats() async {
    final client = api;
    if (client == null) return;
    try {
      stats = await client.stats();
      participants = stats!.participants;
      notifyListeners();
    } on ApiException catch (e) {
      _handleApiError(e);
    }
  }

  Future<void> updateSettings(Map<String, Object> changes) async {
    final client = api;
    if (client == null) return;
    session = await client.updateSettings(changes);
    notifyListeners();
  }

  Future<void> participantAction(String id, String action) async {
    await api?.participantAction(id, action);
    await refreshParticipants();
  }

  /// Host: ends the session for everyone.
  Future<void> endSession({required bool deleteMedia}) async {
    final client = api;
    if (client == null || !isHost) return;
    await client.endSession(deleteMedia: deleteMedia);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await engine.stop();
    await native.stopHostingService();
    await _clearMembership();
    _finish(SessionPhase.ended, deleteMedia ? 'Session ended. Shared media was deleted.' : 'Session ended. Media was kept on this device.');
  }

  /// Participant: leaves the session.
  Future<void> leave() async {
    try {
      await api?.leave();
    } on ApiException {
      // leaving anyway
    }
    await _clearMembership();
    await _teardown();
    phase = SessionPhase.idle;
    role = SessionRole.none;
    notifyListeners();
  }

  /// Returns to the home screen after an ended/removed session.
  void acknowledgeEnd() {
    phase = SessionPhase.idle;
    role = SessionRole.none;
    endedMessage = null;
    notifyListeners();
  }

  void _handleApiError(ApiException e) {
    if (e.sessionEnded) {
      _finish(SessionPhase.ended, 'The host ended this session.');
    } else if (e.isAuth && role == SessionRole.participant) {
      _finish(SessionPhase.removed, e.code == 'blocked' ? 'The host blocked this device.' : 'You are no longer in this session.');
    }
  }

  void _finish(SessionPhase p, String message) {
    if (role == SessionRole.participant) unawaited(_clearMembership());
    unawaited(_teardown());
    phase = p;
    endedMessage = message;
    notifyListeners();
  }

  Future<void> _teardown() async {
    _pendingPoll?.cancel();
    _peopleDebounce?.cancel();
    await _eventSub?.cancel();
    await _statusSub?.cancel();
    _eventSub = null;
    _statusSub = null;
    final rt = _realtime;
    _realtime = null;
    await rt?.dispose();
    uploads.detach();
    downloads.detach();
    gallery.detach();
    api?.close();
    api = null;
    host = null;
    participants = const [];
    stats = null;
    connection = ConnectionStatus.closed;
  }

  // ------------------------------------------------------------------ events

  void _onEvent(ServerEvent e) {
    gallery.handleEvent(e);
    if (!_events.isClosed) _events.add(e);
    switch (e.type) {
      case 'participant_joined' || 'participant_left' || 'participant_status' || 'join_request' || 'media_uploaded' || 'media_deleted':
        _peopleDebounce?.cancel();
        _peopleDebounce = Timer(const Duration(milliseconds: 400), refreshParticipants);
      case 'participant_removed':
        if (e.data['id'] == me?.id && e.data['reason'] != 'left') {
          _finish(SessionPhase.removed, e.data['reason'] == 'blocked' ? 'The host blocked this device.' : 'The host removed you from this session.');
        } else {
          unawaited(refreshParticipants());
        }
      case 'session_updated':
        final s = session;
        if (s != null) {
          session = SessionInfo.fromJson({
            ..._sessionToJson(s),
            ...e.data,
          });
          notifyListeners();
        }
      case 'session_ended':
        if (!isHost) _finish(SessionPhase.ended, 'The host ended this session.');
      case 'network_changed':
        hostUrls = (e.data['urls'] as List?)?.cast<String>() ?? hostUrls;
        joinUrl = e.data['join_url'] as String?;
        networkOk = e.data['network_ok'] == true;
        interfaces = ((e.data['addresses'] as List?) ?? const [])
            .map((x) => NetworkInterfaceInfo.fromJson(x as Map<String, dynamic>))
            .toList();
        notifyListeners();
      case 'storage_warning':
        storageWarning = true;
        notifyListeners();
      case 'resync':
        unawaited(refreshParticipants());
    }
  }

  static Map<String, dynamic> _sessionToJson(SessionInfo s) => {
        'id': s.id,
        'name': s.name,
        'host_name': s.hostName,
        'host_id': s.hostId,
        'created_at': s.createdAt,
        'ended': s.ended,
        'require_approval': s.requireApproval,
        'pin_length': s.pinLength,
        'participant_count': s.participantCount,
        'encrypted': s.encrypted,
        'upload_permission': s.uploadPermission,
        'download_permission': s.downloadPermission,
        'keep_media': s.keepMedia,
        'urls': s.urls,
        'join_url': s.joinUrl,
        'chunk_size': s.chunkSize,
        'max_chunk_size': s.maxChunkSize,
        'max_file_size': s.maxFileSize,
        'pin': s.pin,
        'data_dir': s.dataDir,
      };

  // ------------------------------------------------------------------ lifecycle

  /// Called when the app returns to the foreground.
  Future<void> onResumed() async {
    if (phase != SessionPhase.active) return;
    _realtime?.reconnectNow();
    if (isHost) {
      try {
        final st = await engine.status();
        if (!st.running && !st.ended && host != null) {
          // The OS stopped the server while we were in the background: restart it.
          final h = host!;
          await _teardown();
          await createSession(sessionName: h.sessionName, hostName: h.hostName, resumeId: h.sessionId);
        } else {
          hostUrls = st.urls;
          joinUrl = st.joinUrl;
          networkOk = st.networkOk;
          notifyListeners();
        }
      } on EngineException {
        // keep current state; the next action will surface errors
      }
    } else {
      unawaited(refreshParticipants());
      gallery.refresh();
    }
  }

  @override
  void dispose() {
    _pendingPoll?.cancel();
    _peopleDebounce?.cancel();
    _eventSub?.cancel();
    _statusSub?.cancel();
    _realtime?.dispose();
    _events.close();
    super.dispose();
  }
}
