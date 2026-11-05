import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:localdrop/models/models.dart';
import 'package:localdrop/services/device_library.dart';
import 'package:localdrop/services/download_manager.dart';
import 'package:localdrop/services/engine_service.dart';
import 'package:localdrop/services/preferences.dart';
import 'package:localdrop/services/upload_manager.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A real 32×24 JPEG.
final Uint8List tinyJpeg = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCAAYACADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDwGx0Tp8lb9jonT5K6yw0Tp8n6Vv2GidPkr9YxWceZ4uRZ9tqcnY6J0+St6x0Tp8n6V1thonT5K3rDROnyfpXzuKzjzP2fIs+21M+w0Tp8lb1honT5KKK+axWKqdz+PsixlXTU37DROnyfpW9YaJ0+T9KKK+cxWKqdz9myLGVdNT//2Q==');

/// Unique JPEG: data after the EOI marker is ignored by decoders but changes the hash.
Uint8List uniqueJpeg(int seed) => Uint8List.fromList([...tinyJpeg, ...utf8.encode('localdrop-test-$seed')]);

/// MP4-like file: valid ftyp box followed by pseudo-random bytes.
Uint8List syntheticMp4(int seed, int length) {
  final r = Random(seed);
  final b = Uint8List(length);
  const head = [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d, 0, 0, 2, 0, 0x69, 0x73, 0x6f, 0x6d, 0x6d, 0x70, 0x34, 0x32];
  b.setAll(0, head);
  for (var i = head.length; i < length; i++) {
    b[i] = r.nextInt(256);
  }
  return b;
}

/// Path of the engine built by  (native/engine).
String? engineLibraryPath() {
  final candidates = [
    Platform.environment['LOCALDROP_ENGINE_LIB'],
    '${Directory.current.path}/native/engine/target/debug/liblocaldrop_engine.so',
    '${Directory.current.path}/native/engine/target/release/liblocaldrop_engine.so',
  ];
  for (final c in candidates.whereType<String>()) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

Preferences memoryPreferences() {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  return Preferences();
}

class MemoryUploadStore implements UploadStore {
  final data = <String, List<Map<String, dynamic>>>{};
  @override
  Future<List<Map<String, dynamic>>> load(String sessionId) async => data[sessionId] ?? const [];
  @override
  Future<void> save(String sessionId, List<Map<String, dynamic>> tasks) async => data[sessionId] = tasks;
}

/// Saves into a folder instead of the photo library.
class FolderSaver implements MediaSaver {
  final Directory dir;
  final saved = <String>[];
  FolderSaver(this.dir);
  @override
  Future<String> saveToGallery(String path, {required bool isVideo}) async {
    final target = File('${dir.path}/saved-${saved.length}-${path.split('/').last}');
    await File(path).copy(target.path);
    saved.add(target.path);
    return target.path;
  }

  @override
  Future<Directory> exportDirectory() async => Directory('${dir.path}/exports');
}

/// Engine stand-in for widget tests (no native code).
class FakeEngine implements EngineService {
  List<NetworkInterfaceInfo> ifaces = const [NetworkInterfaceInfo(name: 'wlan0', ip: '192.168.1.20', kind: 'wifi', usable: true)];
  Object? startError;
  @override
  Future<List<NetworkInterfaceInfo>> interfaces() async => ifaces;
  @override
  Future<HostSession> start(EngineConfig config) async => throw startError ?? const EngineException('no engine in widget tests');
  @override
  Future<void> stop() async {}
  @override
  Future<EngineStatus> status() async => const EngineStatus(false, false, [], null, [], false);
  @override
  Future<List<StoredSession>> storedSessions(String dataDir) async => const [];
  @override
  Future<void> deleteSession(String dataDir, String sessionId) async {}
}

Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 20), String? reason}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) throw StateError('Timed out waiting for ${reason ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Phone library with [n] items, newest first; every 4th is a video.
class FakeDeviceLibrary implements DeviceLibrary {
  final int n;
  LibraryAccess accessResult;
  final Set<String> unreadable = {};
  int requests = 0;
  FakeDeviceLibrary(this.n, {this.accessResult = LibraryAccess.full});

  List<DeviceAsset> get all => [
        for (var i = 0; i < n; i++)
          DeviceAsset(
            id: 'asset-$i',
            isVideo: i % 4 == 3,
            createdAt: DateTime(2026, 3, 12).subtract(Duration(minutes: i)),
            duration: i % 4 == 3 ? const Duration(seconds: 32) : Duration.zero,
          ),
      ];

  @override
  Future<LibraryAccess> requestAccess() async {
    requests++;
    return accessResult;
  }

  @override
  Future<int> count() async => n;
  @override
  Future<List<DeviceAsset>> page(int page, int size) async => all.skip(page * size).take(size).toList();
  @override
  Future<Uint8List?> thumbnail(DeviceAsset asset, int size) async => null;
  @override
  Future<({String path, String name})> original(DeviceAsset asset) async {
    if (unreadable.contains(asset.id)) throw const DeviceLibraryException('This item is stored in iCloud and is not on this phone.');
    return (path: '/library/${asset.id}', name: '${asset.id}.${asset.isVideo ? 'mp4' : 'jpg'}');
  }

  @override
  Future<void> openSettings() async {}
  @override
  Future<void> manageLimitedSelection() async {}
}

/// Records queued uploads without touching the file system or network.
class RecordingUploads extends UploadManager {
  final queued = <String>[];
  final cancelled = <String>[];
  RecordingUploads() : super(store: MemoryUploadStore());

  @override
  Future<List<UploadTask>> addFiles(Iterable<({String path, String name, bool isVideo})> files) async {
    final out = <UploadTask>[];
    for (final f in files) {
      queued.add(f.name);
      final t = UploadTask(id: f.name, path: f.path, name: f.name, size: 1, isVideo: f.isVideo);
      tasks.add(t);
      out.add(t);
    }
    return out;
  }

  @override
  Future<void> cancel(UploadTask t) async {
    cancelled.add(t.name);
    t.state = TransferState.cancelled;
  }
}
