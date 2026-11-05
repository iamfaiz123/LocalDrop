import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'hashing.dart';
import 'upload_manager.dart' show TransferState, TransferStateX;

/// Saves finished downloads somewhere the user can find them.
abstract class MediaSaver {
  /// Saves a photo/video into the device gallery. Returns a description of
  /// where it went. Must never overwrite existing files.
  Future<String> saveToGallery(String path, {required bool isVideo});

  /// Directory for exported ZIP archives.
  Future<Directory> exportDirectory();
}

class DownloadTask {
  final String id;
  final String title;
  final MediaItem? media; // single item
  final List<String> exportIds; // ZIP export
  TransferState state = TransferState.queued;
  int received = 0;
  int total;
  double speed = 0;
  String? error;
  String? savedTo;
  bool _stop = false;
  HttpClientResponse? _response;
  StreamSubscription<List<int>>? _sub;
  Completer<void>? _done;

  DownloadTask.media(MediaItem m)
      : id = m.id,
        title = m.filename,
        media = m,
        exportIds = const [],
        total = m.size;

  DownloadTask.export(this.id, this.title, this.exportIds)
      : media = null,
        total = 0;

  bool get isZip => media == null;
  double get progress => total == 0 ? 0 : (state.isFinished ? 1 : received / total);
}

/// Download queue with resume (HTTP Range + If-Range), integrity checks
/// against the uploader's SHA-256, bounded concurrency and gallery saving.
class DownloadManager extends ChangeNotifier {
  final MediaSaver saver;
  final Future<Directory> Function() workDir;
  int maxParallel;
  ApiClient? _api;

  /// Host only: resolves the local path of a media file so saving does not
  /// need a network round trip.
  String? Function(MediaItem m)? localPath;

  final List<DownloadTask> tasks = [];
  Timer? _notifyTimer;

  DownloadManager({required this.saver, required this.workDir, this.maxParallel = 2});

  List<DownloadTask> get active => tasks.where((t) => t.state.isActive).toList();
  List<DownloadTask> get completed => tasks.where((t) => !t.state.isActive).toList();

  void attach(ApiClient api, {String? Function(MediaItem m)? localPath}) {
    _api = api;
    this.localPath = localPath;
    _pump();
  }

  void detach() {
    for (final t in tasks) {
      _abort(t);
      if (t.state.isActive) t.state = TransferState.paused;
    }
    _api = null;
    localPath = null;
    notifyListeners();
  }

  void suspend() {
    for (final t in tasks.where((t) => t.state.isRunning)) {
      _abort(t);
      t.state = TransferState.queued;
    }
    _changed();
  }

  void resumeAll() => _pump();

  /// Queues items; already-queued items are not duplicated.
  void addMedia(Iterable<MediaItem> items) {
    for (final m in items) {
      final existing = tasks.where((t) => t.media?.id == m.id && t.state.isActive);
      if (existing.isNotEmpty) continue;
      tasks.removeWhere((t) => t.media?.id == m.id);
      tasks.add(DownloadTask.media(m));
    }
    _pump();
    notifyListeners();
  }

  /// Exports several items as one ZIP archive. Completes with the file path.
  DownloadTask addExport(List<String> ids, String title) {
    final t = DownloadTask.export('zip-${DateTime.now().microsecondsSinceEpoch}', title, ids);
    tasks.add(t);
    _pump();
    notifyListeners();
    return t;
  }

  void pause(DownloadTask t) {
    _abort(t);
    if (t.state.isActive) t.state = TransferState.paused;
    _changed();
  }

  void resume(DownloadTask t) {
    t.error = null;
    t.state = TransferState.queued;
    _pump();
    _changed();
  }

  Future<void> cancel(DownloadTask t) async {
    _abort(t);
    t.state = TransferState.cancelled;
    final part = await _partFile(t);
    if (await part.exists()) await part.delete();
    _changed();
    _pump();
  }

  void clearFinished() {
    tasks.removeWhere((t) => !t.state.isActive);
    notifyListeners();
  }

  void _abort(DownloadTask t) {
    t._stop = true;
    t._sub?.cancel();
    t._sub = null;
    final done = t._done;
    if (done != null && !done.isCompleted) done.complete();
    final r = t._response;
    t._response = null;
    if (r != null) {
      unawaited(r.detachSocket().then((s) => s.destroy()).catchError((_) {}));
    }
  }

  void _changed() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 150), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void _pump() {
    if (_api == null) return;
    final running = tasks.where((t) => t.state.isRunning).length;
    for (final t in tasks.where((t) => t.state == TransferState.queued).take(max(0, maxParallel - running)).toList()) {
      unawaited(_run(t));
    }
  }

  Future<File> _partFile(DownloadTask t) async {
    final dir = Directory('${(await workDir()).path}/downloads');
    await dir.create(recursive: true);
    final ext = t.media?.ext ?? 'zip';
    return File('${dir.path}/${t.id}.$ext.part');
  }

  Future<void> _run(DownloadTask t) async {
    final api = _api;
    if (api == null) return;
    t._stop = false;
    t.error = null;
    t.state = TransferState.preparing;
    _changed();
    try {
      final m = t.media;
      // Host: the original is already on this device.
      final local = m == null ? null : localPath?.call(m);
      if (m != null && local != null && await File(local).exists()) {
        t.state = TransferState.verifying;
        _changed();
        t.savedTo = await saver.saveToGallery(local, isVideo: m.isVideo);
        t.received = t.total;
        t.state = TransferState.done;
        return;
      }

      String path;
      String? etag;
      if (m != null) {
        path = '/api/media/${m.id}/file';
        etag = '"${m.sha256}"';
      } else {
        final r = await api.createExport(t.exportIds);
        path = r['url'] as String;
        t.total = (r['size'] as num).toInt();
      }
      final part = await _partFile(t);
      var have = await part.exists() ? await part.length() : 0;
      if (m == null) have = 0; // export ids are single-use; restart the zip
      if (have > t.total) {
        await part.delete();
        have = 0;
      }
      t.received = have;
      t.state = TransferState.uploading; // "transferring"
      _changed();

      if (have < t.total || t.total == 0) {
        final res = await api.openDownload(path, from: have, ifRange: etag);
        t._response = res;
        final append = res.statusCode == HttpStatus.partialContent;
        if (!append) t.received = 0;
        if (t.total == 0 && res.contentLength > 0) t.total = res.contentLength;
        final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
        final sw = Stopwatch()..start();
        var lastMs = 0, lastBytes = t.received;
        final done = Completer<void>();
        t._done = done;
        t._sub = res.listen(
          (chunk) {
            sink.add(chunk);
            t.received += chunk.length;
            final ms = sw.elapsedMilliseconds;
            if (ms - lastMs >= 500) {
              final inst = (t.received - lastBytes) * 1000 / (ms - lastMs);
              t.speed = t.speed == 0 ? inst : t.speed * 0.6 + inst * 0.4;
              lastMs = ms;
              lastBytes = t.received;
            }
            _changed();
          },
          onDone: () => done.complete(),
          onError: (Object e) => done.isCompleted ? null : done.completeError(e),
          cancelOnError: true,
        );
        try {
          await done.future;
        } finally {
          await sink.flush();
          await sink.close();
        }
        if (t._stop) throw const _Stopped();
        if (t.received != t.total) {
          throw ApiException(0, 'network', 'Download interrupted at ${t.received} of ${t.total} bytes');
        }
      }

      t.state = TransferState.verifying;
      _changed();
      if (m != null) {
        final sha = await sha256OfFile(part.path);
        if (sha != m.sha256) {
          await part.delete();
          throw const ApiException(0, 'integrity_failed', 'The download was corrupted. Retry to download it again.');
        }
        final named = File('${part.parent.path}/${t.id}.${m.ext}');
        if (await named.exists()) await named.delete();
        await part.rename(named.path);
        try {
          t.savedTo = await saver.saveToGallery(named.path, isVideo: m.isVideo);
        } finally {
          if (await named.exists()) await named.delete();
        }
      } else {
        final dir = await saver.exportDirectory();
        await dir.create(recursive: true);
        final target = await _uniqueFile(dir, t.title);
        await part.rename(target.path).catchError((_) async {
          final f = await part.copy(target.path);
          await part.delete();
          return f;
        });
        t.savedTo = target.path;
      }
      t.state = TransferState.done;
    } on _Stopped {
      if (t.state != TransferState.cancelled) t.state = TransferState.paused;
    } on ApiException catch (e) {
      if (t._stop) {
        if (t.state != TransferState.cancelled) t.state = TransferState.paused;
      } else {
        t.state = TransferState.failed;
        t.error = e.message;
      }
    } on Exception catch (e) {
      if (t._stop) {
        if (t.state != TransferState.cancelled) t.state = TransferState.paused;
      } else {
        t.state = TransferState.failed;
        t.error = e is FileSystemException ? 'Could not save: ${e.message}' : '$e';
      }
    } finally {
      t._sub = null;
      t._done = null;
      t._response = null;
      _changed();
      _pump();
    }
  }

  /// `name.zip`, `name (2).zip`, … — never overwrites an existing file.
  static Future<File> _uniqueFile(Directory dir, String name) async {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = File('${dir.path}/$name');
    var i = 2;
    while (await candidate.exists()) {
      candidate = File('${dir.path}/$stem ($i)$ext');
      i++;
    }
    return candidate;
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
