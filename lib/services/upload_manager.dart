import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../platform/native_bridge.dart';
import 'api_client.dart';
import 'hashing.dart';

enum TransferState { queued, preparing, uploading, paused, verifying, done, duplicate, failed, cancelled }

extension TransferStateX on TransferState {
  bool get isActive => const {
        TransferState.queued,
        TransferState.preparing,
        TransferState.uploading,
        TransferState.paused,
        TransferState.verifying,
        TransferState.failed,
      }.contains(this);
  bool get isRunning => this == TransferState.preparing || this == TransferState.uploading || this == TransferState.verifying;
  bool get isFinished => this == TransferState.done || this == TransferState.duplicate;
}

class UploadTask {
  final String id;
  final String path;
  final String name;
  final int size;
  final bool isVideo;
  TransferState state = TransferState.queued;
  int sent = 0;
  double speed = 0;
  String? error;
  String? sha256;
  String? uploadId;
  MediaItem? media;
  int retries = 0;
  bool _stop = false;
  HttpClientRequest? _request;

  UploadTask({required this.id, required this.path, required this.name, required this.size, required this.isVideo});

  double get progress => size == 0 ? 0 : (state.isFinished ? 1 : sent / size);

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'name': name, 'size': size, 'video': isVideo, 'sha256': sha256};
  static UploadTask fromJson(Map<String, dynamic> j) => UploadTask(
        id: j['id'] as String,
        path: j['path'] as String,
        name: j['name'] as String,
        size: (j['size'] as num).toInt(),
        isVideo: j['video'] == true,
      )..sha256 = j['sha256'] as String?;
}

/// Persists unfinished uploads so they resume after the app is killed.
abstract class UploadStore {
  Future<void> save(String sessionId, List<Map<String, dynamic>> tasks);
  Future<List<Map<String, dynamic>>> load(String sessionId);
}

/// Upload queue: bounded concurrency, chunked streaming from disk,
/// pause/resume, automatic retry with backoff, resume after restarts,
/// full-file SHA-256 verification and client-side thumbnails.
class UploadManager extends ChangeNotifier {
  final NativeBridge native;
  final UploadStore? store;
  int maxParallel;
  final String? tempDir;
  ApiClient? _api;
  String? _sessionId;
  final List<UploadTask> tasks = [];
  int _seq = 0;
  Timer? _notifyTimer;
  bool _dirty = false;

  UploadManager({this.native = const NativeBridge(), this.store, this.maxParallel = 2, this.tempDir});

  List<UploadTask> get active => tasks.where((t) => t.state.isActive).toList();
  List<UploadTask> get completed => tasks.where((t) => !t.state.isActive).toList();
  int get runningCount => tasks.where((t) => t.state.isRunning || t.state == TransferState.queued).length;

  /// Binds the queue to a session. Restores persisted unfinished uploads.
  Future<void> attach(ApiClient api, String sessionId) async {
    _api = api;
    if (_sessionId == sessionId) {
      _pump();
      return;
    }
    _sessionId = sessionId;
    tasks.clear();
    final saved = await store?.load(sessionId) ?? const [];
    for (final j in saved) {
      final t = UploadTask.fromJson(j);
      if (await File(t.path).exists()) tasks.add(t);
    }
    _pump();
    notifyListeners();
  }

  void detach() {
    for (final t in tasks) {
      _abort(t);
    }
    _api = null;
    _sessionId = null;
    tasks.clear();
    notifyListeners();
  }

  /// Pauses network activity (e.g. connection lost) without forgetting tasks.
  void suspend() {
    for (final t in tasks.where((t) => t.state.isRunning)) {
      _abort(t);
      t.state = TransferState.queued;
    }
    _changed();
  }

  void resumeAll() => _pump();

  Future<void> addFiles(Iterable<({String path, String name, bool isVideo})> files) async {
    for (final f in files) {
      final file = File(f.path);
      if (!await file.exists()) continue;
      final size = await file.length();
      tasks.add(UploadTask(id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}', path: f.path, name: f.name, size: size, isVideo: f.isVideo));
    }
    await _persist();
    _pump();
    notifyListeners();
  }

  void pause(UploadTask t) {
    _abort(t);
    if (t.state.isActive) t.state = TransferState.paused;
    _changed();
  }

  void resume(UploadTask t) {
    t.retries = 0;
    t.error = null;
    t.state = TransferState.queued;
    _pump();
    _changed();
  }

  Future<void> cancel(UploadTask t) async {
    _abort(t);
    t.state = TransferState.cancelled;
    _changed();
    final id = t.uploadId;
    final api = _api;
    if (id != null && api != null) {
      for (var i = 0; i < 5; i++) {
        try {
          await api.cancelUpload(id);
          break;
        } on ApiException catch (e) {
          if (e.code != 'upload_busy') break;
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    await _cleanupTemp(t);
    await _persist();
    _pump();
  }

  void clearFinished() {
    tasks.removeWhere((t) => !t.state.isActive);
    notifyListeners();
  }

  void _abort(UploadTask t) {
    t._stop = true;
    t._request?.abort();
    t._request = null;
  }

  void _changed() {
    _dirty = true;
    _notifyTimer ??= Timer(const Duration(milliseconds: 150), () {
      _notifyTimer = null;
      if (_dirty) {
        _dirty = false;
        notifyListeners();
      }
    });
  }

  void _pump() {
    if (_api == null) return;
    final running = tasks.where((t) => t.state.isRunning).length;
    final free = max(0, maxParallel - running);
    for (final t in tasks.where((t) => t.state == TransferState.queued).take(free).toList()) {
      unawaited(_run(t));
    }
  }

  Future<void> _persist() async {
    final sid = _sessionId;
    if (sid == null || store == null) return;
    await store!.save(sid, tasks.where((t) => t.state.isActive).map((t) => t.toJson()).toList());
  }

  Future<void> _run(UploadTask t) async {
    final api = _api;
    if (api == null) return;
    t._stop = false;
    t.error = null;
    t.state = TransferState.preparing;
    _changed();
    try {
      final file = File(t.path);
      if (!await file.exists()) throw const ApiException(0, 'file_missing', 'The file is no longer available on this device');
      t.sha256 ??= await sha256OfFile(t.path);
      await _persist();
      if (t._stop) throw const _Stopped();

      final created = await api.createUpload(t.name, t.size, sha256: t.sha256);
      if (created['duplicate'] == true) {
        t.media = MediaItem.fromJson(created['media'] as Map<String, dynamic>);
        t.state = TransferState.duplicate;
        return;
      }
      t.uploadId = created['upload_id'] as String;
      final chunk = max(256 * 1024, min((created['chunk_size'] as num).toInt(), (created['max_chunk_size'] as num).toInt()));
      var offset = (created['received'] as num).toInt();
      t.sent = offset;
      t.state = TransferState.uploading;
      _changed();

      final sw = Stopwatch()..start();
      var lastBytes = offset;
      var lastMs = 0;
      while (offset < t.size) {
        if (t._stop) throw const _Stopped();
        final end = min(offset + chunk, t.size);
        try {
          final r = await api.putChunk(
            t.uploadId!,
            offset,
            file.openRead(offset, end),
            end - offset,
            onRequest: (req) => t._request = req,
            onProgress: (n) {
              t.sent = offset + n;
              final ms = sw.elapsedMilliseconds;
              if (ms - lastMs >= 500) {
                final inst = (t.sent - lastBytes) * 1000 / (ms - lastMs);
                t.speed = t.speed == 0 ? inst : t.speed * 0.6 + inst * 0.4;
                lastMs = ms;
                lastBytes = t.sent;
              }
              _changed();
            },
          );
          t._request = null;
          offset = (r['received'] as num).toInt();
          t.retries = 0;
        } on ApiException catch (e) {
          t._request = null;
          if (e.code == 'offset_mismatch' && e.details['received'] is num) {
            offset = (e.details['received'] as num).toInt();
            continue;
          }
          rethrow;
        }
        t.sent = offset;
        _changed();
      }

      t.state = TransferState.verifying;
      _changed();
      final done = await api.completeUpload(t.uploadId!, t.sha256!);
      t.media = MediaItem.fromJson(done['media'] as Map<String, dynamic>);
      t.state = done['duplicate'] == true ? TransferState.duplicate : TransferState.done;
      t.sent = t.size;
      _changed();
      // Generate the thumbnail before the temp copy (if any) is cleaned up.
      if (done['needs_client_thumbnail'] == true) await _clientThumbnail(api, t);
    } on _Stopped {
      if (t.state != TransferState.cancelled) t.state = TransferState.paused;
    } on ApiException catch (e) {
      if (t._stop) {
        if (t.state != TransferState.cancelled) t.state = TransferState.paused;
      } else if (_retryable(e) && t.retries < 6) {
        t.retries++;
        t.error = '${e.message} — retrying…';
        t.state = TransferState.paused;
        _changed();
        await Future<void>.delayed(Duration(seconds: min(30, 1 << t.retries)));
        if (t.state == TransferState.paused && !t._stop) t.state = TransferState.queued;
      } else {
        t.state = TransferState.failed;
        t.error = switch (e.code) {
          'insufficient_storage' => 'The host is out of storage space',
          'integrity_failed' => 'The file was corrupted in transit. Retry to upload it again.',
          'unsupported_type' || 'unsupported_content' => 'Only photos and videos can be shared',
          _ => e.message,
        };
      }
    } on FileSystemException catch (e) {
      t.state = TransferState.failed;
      t.error = 'Cannot read the file: ${e.message}';
    } finally {
      t._request = null;
      if (t.state.isFinished) await _cleanupTemp(t);
      await _persist();
      _changed();
      _pump();
    }
  }

  bool _retryable(ApiException e) =>
      e.isNetwork || e.status >= 500 && e.status != 507 || e.status == 429 || e.code == 'upload_busy';

  Future<void> _clientThumbnail(ApiClient api, UploadTask t) async {
    final m = t.media;
    if (m == null) return;
    final jpeg = await native.thumbnail(t.path, video: m.isVideo);
    if (jpeg == null) return;
    try {
      await api.putThumbnail(m.id, jpeg);
    } on ApiException catch (e) {
      debugPrint('LocalDrop: thumbnail upload failed for ${t.name}: $e');
    }
  }

  /// Removes copies the picker placed in our temp directory once they are
  /// safely on the host. Original files elsewhere are never touched.
  Future<void> _cleanupTemp(UploadTask t) async {
    final tmp = tempDir;
    if (tmp == null || !t.path.startsWith(tmp)) return;
    try {
      await File(t.path).delete();
    } on FileSystemException {
      // already gone
    }
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    for (final t in tasks) {
      _abort(t);
    }
    super.dispose();
  }
}

class _Stopped implements Exception {
  const _Stopped();
}

/// JSON-in-preferences implementation of [UploadStore].
class JsonUploadStore implements UploadStore {
  final Future<void> Function(String key, String value) write;
  final Future<String?> Function(String key) read;
  JsonUploadStore({required this.write, required this.read});

  @override
  Future<void> save(String sessionId, List<Map<String, dynamic>> tasks) => write('uploads.$sessionId', jsonEncode(tasks));

  @override
  Future<List<Map<String, dynamic>>> load(String sessionId) async {
    final s = await read('uploads.$sessionId');
    if (s == null) return const [];
    try {
      return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    } on FormatException {
      return const [];
    }
  }
}
