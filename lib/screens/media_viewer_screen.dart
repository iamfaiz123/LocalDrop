import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../providers/gallery_controller.dart';
import '../providers/session_controller.dart';
import '../services/api_client.dart';
import '../services/download_manager.dart';
import '../services/share_service.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';

class MediaViewerScreen extends StatefulWidget {
  final int initialIndex;
  const MediaViewerScreen({super.key, required this.initialIndex});
  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _sharing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GalleryController>();
    final s = context.watch<SessionController>();
    final api = g.api;
    if (api == null || g.items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
      return const Scaffold(backgroundColor: Color(0xFF11121A));
    }
    if (_index >= g.items.length) _index = g.items.length - 1;
    final m = g.items[_index];
    final canDownload = s.isHost || (s.session?.downloadsOpen ?? true);
    return Scaffold(
      backgroundColor: const Color(0xFF11121A),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Row(children: [
              IconButton(
                  tooltip: 'Back', icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
              const Spacer(),
              Text('${_index + 1} of ${g.total}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (v) async {
                  if (v == 'delete') {
                    final ok = await confirmDialog(context,
                        title: 'Delete for everyone?',
                        message: '“${m.filename}” will be removed from the shared gallery. This cannot be undone.',
                        confirm: 'Delete',
                        destructive: true);
                    if (!ok || !context.mounted) return;
                    final (deleted, _, failed) = await g.delete([m]);
                    if (context.mounted) showToast(context, deleted == 1 ? 'Deleted' : 'Could not delete', error: failed > 0);
                  } else if (v == 'info') {
                    _showInfo(context, m);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'info', child: Text('Details')),
                  if (g.canDelete(m)) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: g.items.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                if (i >= g.items.length - 5) g.loadMore();
              },
              itemBuilder: (_, i) {
                final item = g.items[i];
                final local = s.isHost && s.host != null ? '${s.host!.sessionDir}/media/${item.id}.${item.ext}' : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: item.isVideo
                      ? _VideoView(key: ValueKey(item.id), item: item, api: api, localPath: local, active: i == _index)
                      : _PhotoView(key: ValueKey(item.id), item: item, api: api),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 14),
            child: Row(children: [
              CircleAvatar(
                  radius: 16,
                  backgroundColor: avatarColor(m.uploader.avatarColor),
                  child: Text(m.uploader.initials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
              const SizedBox(width: 9),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.uploader.id == s.me?.id ? '${m.uploader.name} (you)' : m.uploader.name,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text('${formatTimestamp(m.createdAt)} · ${formatBytes(m.size)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
              IconButton(
                tooltip: 'Share',
                icon: _sharing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.share_outlined, color: Colors.white),
                onPressed: _sharing || !canDownload
                    ? null
                    : () async {
                        setState(() => _sharing = true);
                        try {
                          await ShareService(api, hostSessionDir: s.isHost ? s.host?.sessionDir : null).share([m]);
                        } on Exception catch (e) {
                          if (context.mounted) showToast(context, 'Could not share: $e', error: true);
                        } finally {
                          if (mounted) setState(() => _sharing = false);
                        }
                      },
              ),
              IconButton(
                tooltip: 'Save original to gallery',
                icon: const Icon(Icons.download_outlined, color: Colors.white),
                onPressed: !canDownload
                    ? null
                    : () {
                        context.read<DownloadManager>().addMedia([m]);
                        showToast(context, 'Saving original to your gallery…');
                      },
              ),
              IconButton(
                tooltip: m.favorite ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(m.favorite ? Icons.favorite : Icons.favorite_border, color: m.favorite ? const Color(0xFFFF6B81) : Colors.white),
                onPressed: () async {
                  try {
                    await g.toggleFavorite(m);
                  } on ApiException catch (e) {
                    if (context.mounted) showToast(context, e.message, error: true);
                  }
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showInfo(BuildContext context, MediaItem m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.filename, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          _kv('Shared by', m.uploader.name),
          _kv('Uploaded', formatTimestamp(m.createdAt)),
          _kv('Size', formatBytes(m.size)),
          _kv('Type', m.mime),
          if (m.width != null) _kv('Dimensions', '${m.width} × ${m.height}'),
          _kv('SHA-256', m.sha256),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96, child: Text(k, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class _PhotoView extends StatelessWidget {
  final MediaItem item;
  final ApiClient api;
  const _PhotoView({super.key, required this.item, required this.api});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Decode at screen resolution (×2 for zoom) to bound memory for 50 MP photos.
    final decodeWidth = (mq.size.width * mq.devicePixelRatio * 2).clamp(800, 4096).round();
    return InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image.network(
          api.fileUrl(item.id),
          headers: api.authHeaders,
          cacheWidth: (item.width != null && item.width! < decodeWidth) ? null : decodeWidth,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Stack(alignment: Alignment.center, children: [
                  if (item.hasThumbnail)
                    Image.network(api.thumbnailUrl(item), headers: api.authHeaders, fit: BoxFit.contain),
                  CircularProgressIndicator(
                    color: Colors.white,
                    value: progress.expectedTotalBytes == null ? null : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                  ),
                ]),
          errorBuilder: (_, __, ___) => const Text(
            'This photo can’t be shown here. Save it to view it in your gallery.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _VideoView extends StatefulWidget {
  final MediaItem item;
  final ApiClient api;
  final String? localPath;
  final bool active;
  const _VideoView({super.key, required this.item, required this.api, required this.localPath, required this.active});
  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  VideoPlayerController? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final local = widget.localPath;
    final c = local != null && File(local).existsSync()
        ? VideoPlayerController.file(File(local))
        : VideoPlayerController.networkUrl(Uri.parse(widget.api.fileUrl(widget.item.id)), httpHeaders: widget.api.authHeaders);
    _c = c;
    try {
      await c.initialize();
      if (mounted) setState(() {});
    } on Exception catch (_) {
      if (mounted) setState(() => _error = 'This video can’t be played here. Save it to watch it in your gallery.');
    }
  }

  @override
  void didUpdateWidget(_VideoView old) {
    super.didUpdateWidget(old);
    if (!widget.active) _c?.pause();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)));
    }
    if (c == null || !c.value.isInitialized) {
      return Stack(alignment: Alignment.center, children: [
        if (widget.item.hasThumbnail)
          Image.network(widget.api.thumbnailUrl(widget.item), headers: widget.api.authHeaders, fit: BoxFit.contain),
        const CircularProgressIndicator(color: Colors.white),
      ]);
    }
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        ValueListenableBuilder(
          valueListenable: c,
          builder: (_, v, __) => v.isPlaying
              ? const SizedBox.shrink()
              : const CircleAvatar(
                  radius: 30, backgroundColor: Color(0x99000000), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40)),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 0,
          child: VideoProgressIndicator(c,
              allowScrubbing: true,
              colors: const VideoProgressColors(playedColor: Color(0xFF8C6BFF), bufferedColor: Colors.white30, backgroundColor: Colors.white12)),
        ),
      ]),
    );
  }
}
