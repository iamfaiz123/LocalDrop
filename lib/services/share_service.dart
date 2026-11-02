import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Shares originals through the system share sheet. The host shares its
/// local files directly; participants fetch originals to a temp folder first.
class ShareService {
  final ApiClient api;
  final String? hostSessionDir;
  ShareService(this.api, {this.hostSessionDir});

  static const maxItems = 20;

  Future<void> share(List<MediaItem> items, {void Function(int done, int total)? onProgress}) async {
    if (items.isEmpty) return;
    final files = <XFile>[];
    final tmp = Directory('${(await getTemporaryDirectory()).path}/share');
    await tmp.create(recursive: true);
    for (final (i, m) in items.take(maxItems).indexed) {
      onProgress?.call(i, items.length);
      final local = hostSessionDir == null ? null : File('$hostSessionDir/media/${m.id}.${m.ext}');
      if (local != null && await local.exists()) {
        files.add(XFile(local.path, name: m.filename, mimeType: m.mime));
        continue;
      }
      final target = File('${tmp.path}/${m.id}.${m.ext}');
      if (!await target.exists() || await target.length() != m.size) {
        final res = await api.openDownload('/api/media/${m.id}/file');
        final sink = target.openWrite();
        await res.pipe(sink);
      }
      files.add(XFile(target.path, name: m.filename, mimeType: m.mime));
    }
    await SharePlus.instance.share(ShareParams(files: files));
  }
}
