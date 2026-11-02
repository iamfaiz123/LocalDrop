import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/gallery_controller.dart';
import '../providers/session_controller.dart';
import '../services/realtime_service.dart';
import '../services/upload_manager.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'media_viewer_screen.dart';
import 'selection_screen.dart';

const _videoExtensions = {'mp4', 'm4v', 'mov', '3gp', '3g2', 'webm', 'mkv', 'avi'};

/// Opens the system photo/video picker and queues the selection.
Future<void> pickAndUpload(BuildContext context) async {
  final s = context.read<SessionController>();
  final uploads = context.read<UploadManager>();
  if (s.session?.uploadsOpen == false && !s.isHost) {
    showToast(context, 'The host has turned off uploads', error: true);
    return;
  }
  final List<XFile> files;
  try {
    // No resize/quality options: originals are kept byte-for-byte.
    files = await ImagePicker().pickMultipleMedia(requestFullMetadata: true);
  } on Exception catch (e) {
    if (context.mounted) showToast(context, 'Could not open your photos: $e', error: true);
    return;
  }
  if (files.isEmpty) return;
  await uploads.addFiles(files.map((f) {
    final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    final isVideo = (f.mimeType?.startsWith('video/') ?? false) || _videoExtensions.contains(ext);
    return (path: f.path, name: f.name, isVideo: isVideo);
  }));
  if (context.mounted) showToast(context, '${files.length} file${files.length == 1 ? '' : 's'} added to uploads');
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 900) context.read<GalleryController>().loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final g = context.watch<GalleryController>();
    final api = g.api;
    final members = s.activeMembers == 0 ? (s.session?.participantCount ?? 1) : s.activeMembers;
    final canUpload = s.isHost || (s.session?.uploadsOpen ?? true);

    return Stack(children: [
      RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await Future.wait([g.refresh(), s.refreshParticipants()]);
        },
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.session?.name ?? '',
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7)),
                  const SizedBox(height: 5),
                  Text('$members member${members == 1 ? '' : 's'} · ${g.total} item${g.total == 1 ? '' : 's'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 22),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (f, label) in const [
                        (MediaFilter.all, 'All'),
                        (MediaFilter.photos, 'Photos'),
                        (MediaFilter.videos, 'Videos'),
                        (MediaFilter.favorites, 'Favorites'),
                      ]) ...[
                        Pill(label, selected: g.filter == f, onTap: () => g.setFilter(f)),
                        const SizedBox(width: 7),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(child: _UploaderFilter(controller: g, session: s)),
                    GestureDetector(
                      onTap: g.toggleOrder,
                      child: Text(g.ascending ? 'Oldest first' : 'Newest first',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (s.connection == ConnectionStatus.reconnecting)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: InfoBanner('Connection to the host was lost. Reconnecting…', icon: Icons.wifi_off_rounded),
                    ),
                ]),
              ),
            ),
            if (g.error != null && g.items.isEmpty)
              SliverToBoxAdapter(
                child: StateMessage(
                  icon: Icons.wifi_off_rounded,
                  title: 'Couldn’t load the gallery',
                  detail: g.error,
                  action: 'Try again',
                  onAction: g.refresh,
                ),
              )
            else if (g.isEmpty)
              SliverToBoxAdapter(
                child: StateMessage(
                  icon: Icons.photo_library_outlined,
                  title: g.filter == MediaFilter.all ? 'No photos or videos yet' : 'Nothing here yet',
                  detail: g.filter == MediaFilter.all
                      ? 'Tap “Upload photos & videos” to share the first ones.'
                      : 'Try another filter.',
                ),
              )
            else if (api != null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .82),
                  itemCount: g.items.length,
                  itemBuilder: (context, i) {
                    final m = g.items[i];
                    return MediaTile(
                      key: ValueKey(m.id),
                      item: m,
                      api: api,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaViewerScreen(initialIndex: i))),
                      onLongPress: () {
                        g.startSelection(m.id);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectionScreen()));
                      },
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 100),
                child: Center(
                  child: g.loading
                      ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3))
                      : (g.error != null && g.items.isNotEmpty)
                          ? TextButton(onPressed: g.loadMore, child: const Text('Couldn’t load more — tap to retry'))
                          : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        bottom: 16,
        child: Row(children: [
          Expanded(
            child: PrimaryButton(
              label: canUpload ? 'Upload photos & videos' : 'Uploads are turned off',
              icon: Icons.add,
              onPressed: canUpload ? () => pickAndUpload(context) : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 54,
            height: 54,
            child: OutlinedButton(
              key: const Key('selectButton'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: g.items.isEmpty
                  ? null
                  : () {
                      g.startSelection();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectionScreen()));
                    },
              child: const Icon(Icons.checklist_rounded, color: AppColors.primary),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _UploaderFilter extends StatelessWidget {
  final GalleryController controller;
  final SessionController session;
  const _UploaderFilter({required this.controller, required this.session});

  @override
  Widget build(BuildContext context) {
    final people = session.participants.where((p) => p.isActive || p.items > 0).toList();
    final current = people.where((p) => p.id == controller.uploaderId).firstOrNull;
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        tooltip: 'Filter by person',
        onSelected: (id) => controller.setUploader(id.isEmpty ? null : id),
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('Everyone')),
          for (final p in people)
            PopupMenuItem(value: p.id, child: Text(p.id == session.me?.id ? '${p.name} (you)' : p.name)),
        ],
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(current == null ? 'Everyone' : current.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Icon(Icons.expand_more, size: 20),
        ]),
      ),
    );
  }
}
