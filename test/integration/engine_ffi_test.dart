// Drives the real Rust engine (loaded with dart:ffi) through the app's Dart
// services: session creation, joining, chunked/resumable uploads, realtime
// events, gallery, downloads with integrity checks and ZIP export.
//
// Requires `cargo build --manifest-path native/engine/Cargo.toml` first
// (or LOCALDROP_ENGINE_LIB pointing at the library). Skipped otherwise.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/models/models.dart';
import 'package:localdrop/providers/gallery_controller.dart';
import 'package:localdrop/providers/session_controller.dart';
import 'package:localdrop/services/api_client.dart';
import 'package:localdrop/services/download_manager.dart';
import 'package:localdrop/services/engine_service.dart';
import 'package:localdrop/services/realtime_service.dart';
import 'package:localdrop/services/upload_manager.dart';

import '../support.dart';

void main() {
  final lib = engineLibraryPath();
  final skip = lib == null ? 'Engine library not built (cargo build in native/engine)' : null;
  late Directory tmp;
  late FfiEngineService engine;

  setUpAll(() {
    if (lib != null) FfiEngineService.libraryPathOverride = lib;
    engine = FfiEngineService();
  });
  setUp(() async => tmp = await Directory.systemTemp.createTemp('ld_ffi_'));
  tearDown(() async {
    await engine.stop();
    await tmp.delete(recursive: true);
  });

  Future<HostSession> startHost({bool approval = false}) => engine.start(EngineConfig(
        dataDir: '${tmp.path}/data',
        sessionName: 'Manali Trip 2026',
        hostName: 'Aarav',
        port: 0,
        requireApproval: approval,
        chunkSizeMiB: 1,
      ));

  Future<File> writeFile(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  test('engine lifecycle, status and interfaces through FFI', () async {
    final ifaces = await engine.interfaces();
    expect(ifaces, isA<List<NetworkInterfaceInfo>>());
    final h = await startHost();
    expect(h.pin, hasLength(6));
    expect(h.hostToken, hasLength(64));
    final st = await engine.status();
    expect(st.running, isTrue);
    // Starting twice is refused.
    await expectLater(startHost(), throwsA(isA<EngineException>()));
    final stored = await engine.storedSessions('${tmp.path}/data');
    expect(stored.single.id, h.sessionId);
    await engine.stop();
    expect((await engine.status()).running, isFalse);
    // Data survives; the session can be resumed with the same PIN.
    final resumed = await engine.start(EngineConfig(dataDir: '${tmp.path}/data', port: 0, resumeSessionId: h.sessionId));
    expect(resumed.resumed, isTrue);
    expect(resumed.pin, h.pin);
  }, skip: skip);

  test('join, upload (chunked), realtime, gallery and verified download', () async {
    final h = await startHost();
    final host = ApiClient(Uri.parse(h.localUrl), token: h.hostToken);
    final rt = RealtimeService(host);
    final events = <String>[];
    rt.events.listen((e) => events.add(e.type));
    await rt.connect();
    await waitFor(() => rt.status == ConnectionStatus.connected, reason: 'websocket');

    final guest = ApiClient(Uri.parse(h.localUrl));
    await expectLater(guest.join(name: 'Riya', pin: '000000x'), throwsA(isA<ApiException>()));
    final (me, info) = await guest.join(name: 'Riya', pin: h.pin, deviceId: 'device-riya');
    expect(me.name, 'Riya');
    expect(info.name, 'Manali Trip 2026');
    expect(info.pin, isNull, reason: 'participants never see the PIN');

    final uploads = UploadManager(store: MemoryUploadStore());
    await uploads.attach(guest, info.id);
    final photo = await writeFile('IMG_4829.JPG', uniqueJpeg(1));
    final videoBytes = syntheticMp4(7, 3 * 1024 * 1024 + 123); // 4 chunks of 1 MiB
    final video = await writeFile('VID_0193.MP4', videoBytes);
    await uploads.addFiles([
      (path: photo.path, name: 'IMG_4829.JPG', isVideo: false),
      (path: video.path, name: 'VID_0193.MP4', isVideo: true),
    ]);
    await waitFor(() => uploads.tasks.every((t) => t.state == TransferState.done), reason: 'uploads');
    expect(uploads.tasks.map((t) => t.media!.kind), containsAll(['photo', 'video']));

    final gallery = GalleryController();
    gallery.attach(guest, meId: me.id, isHost: false);
    await waitFor(() => gallery.loadedOnce && gallery.items.length == 2, reason: 'gallery');
    expect(gallery.items.first.uploader.name, 'Riya');
    await waitFor(() => events.contains('media_uploaded') && events.contains('participant_status'), reason: 'events');

    // Duplicate detection before sending any bytes.
    await uploads.addFiles([(path: photo.path, name: 'copy.jpg', isVideo: false)]);
    await waitFor(() => uploads.tasks.last.state == TransferState.duplicate, reason: 'duplicate');

    // Download the video as the host and verify it byte-for-byte.
    final saver = FolderSaver(await Directory('${tmp.path}/saved').create());
    final downloads = DownloadManager(saver: saver, workDir: () async => tmp);
    downloads.attach(host);
    final vid = gallery.items.firstWhere((m) => m.isVideo);
    downloads.addMedia([vid]);
    await waitFor(() => downloads.tasks.single.state == TransferState.done, reason: 'download');
    expect(await File(saver.saved.single).readAsBytes(), videoBytes);

    // ZIP export of both items.
    final zip = downloads.addExport(gallery.items.map((m) => m.id).toList(), 'trip.zip');
    await waitFor(() => zip.state == TransferState.done, reason: 'zip export');
    final zipFile = File(zip.savedTo!);
    expect(await zipFile.length(), greaterThan(videoBytes.length));
    expect((await zipFile.openRead(0, 4).first), [0x50, 0x4b, 0x03, 0x04]);

    // Favorites + delete round trip.
    await gallery.toggleFavorite(gallery.items.first);
    expect((await guest.listMedia(favorites: true)).total, 1);
    final (deleted, skipped, failed) = await gallery.delete([gallery.items.first]);
    expect((deleted, skipped, failed), (1, 0, 0));
    await waitFor(() => events.contains('media_deleted'), reason: 'media_deleted');

    uploads.dispose();
    downloads.dispose();
    await rt.dispose();
    host.close();
    guest.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('pause, resume and recovery after the app restarts', () async {
    final h = await startHost();
    final guest = ApiClient(Uri.parse(h.localUrl));
    final (_, info) = await guest.join(name: 'Karan', pin: h.pin, deviceId: 'device-k');
    final store = MemoryUploadStore();
    final bytes = syntheticMp4(11, 12 * 1024 * 1024);
    final file = await writeFile('long.mp4', bytes);

    final first = UploadManager(store: store, maxParallel: 1);
    await first.attach(guest, info.id);
    await first.addFiles([(path: file.path, name: 'long.mp4', isVideo: true)]);
    final task = first.tasks.single;
    await waitFor(() => task.sent >= 2 * 1024 * 1024, reason: 'partial progress');
    first.pause(task);
    await waitFor(() => task.state == TransferState.paused, reason: 'paused');
    final pausedAt = task.sent;
    expect(pausedAt, lessThan(bytes.length));
    expect((await guest.listMedia()).total, 0, reason: 'partial uploads are hidden');

    // "App killed": a new manager restores the task from the store and resumes.
    first.dispose();
    final second = UploadManager(store: store, maxParallel: 1);
    await second.attach(guest, info.id);
    expect(second.tasks, hasLength(1));
    await waitFor(() => second.tasks.single.state == TransferState.done, reason: 'resumed upload', timeout: const Duration(seconds: 60));
    final media = second.tasks.single.media!;
    expect(media.sha256, sha256.convert(bytes).toString());
    expect(media.size, bytes.length);
    second.dispose();
    guest.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('SessionController: host creates, participant joins with approval, host ends', () async {
    final prefs = memoryPreferences();
    SessionController controller(String name) => SessionController(
          engine: engine,
          prefs: prefs,
          dataDir: () async => '${tmp.path}/data-$name',
          gallery: GalleryController(),
          uploads: UploadManager(store: MemoryUploadStore()),
          downloads: DownloadManager(saver: FolderSaver(tmp), workDir: () async => tmp),
        );
    final hostC = controller('host');
    final ok = await hostC.createSession(sessionName: 'Goa', hostName: 'Aarav', requireApproval: true);
    expect(ok, isTrue, reason: hostC.steps.map((s) => '${s.label}: ${s.state} ${s.detail}').join('\n'));
    expect(hostC.isHost, isTrue);
    expect(hostC.steps.every((s) => s.state == StartStepState.done || s.state == StartStepState.warning), isTrue);
    await waitFor(() => hostC.connection == ConnectionStatus.connected, reason: 'host realtime');

    final guestC = controller('guest');
    final (base, info) = await guestC.probe(hostC.host!.localUrl);
    expect(info.name, 'Goa');
    await expectLater(guestC.probe('not a url'), throwsA(isA<ApiException>()));
    final status = await guestC.join(base, name: 'Meera', pin: hostC.session!.pin!);
    expect(status, 'pending');
    expect(guestC.phase, SessionPhase.pending);

    await waitFor(() => hostC.pendingRequests.isNotEmpty, reason: 'join request on host');
    await hostC.participantAction(hostC.pendingRequests.single.id, 'approve');
    await waitFor(() => guestC.phase == SessionPhase.active, reason: 'approval', timeout: const Duration(seconds: 15));
    await waitFor(() => guestC.connection == ConnectionStatus.connected, reason: 'guest realtime');

    await hostC.updateSettings({'upload_permission': 'host_only'});
    await waitFor(() => guestC.session?.uploadPermission == 'host_only', reason: 'session_updated event');

    await hostC.endSession(deleteMedia: false);
    expect(hostC.phase, SessionPhase.ended);
    await waitFor(() => guestC.phase == SessionPhase.ended, reason: 'session_ended event');
    expect(guestC.endedMessage, contains('ended'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
