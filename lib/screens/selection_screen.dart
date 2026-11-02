import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/gallery_controller.dart';
import '../providers/session_controller.dart';
import '../services/download_manager.dart';
import '../services/share_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';

/// Multi-select: download originals, share, export as ZIP, delete.
class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});
  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  bool _busy = false;
  late final GalleryController _gallery = context.read<GalleryController>();

  @override
  void dispose() {
    _gallery.endSelection();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (e) {
      if (mounted) showToast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GalleryController>();
    final s = context.watch<SessionController>();
    final api = g.api;
    final selected = g.selectedItems;
    final canDownload = s.isHost || (s.session?.downloadsOpen ?? true);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          AppHeader(
            leading: IconButton(
                tooltip: 'Done', icon: const Icon(Icons.close), visualDensity: VisualDensity.compact, onPressed: () => Navigator.pop(context)),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) g.loadMore();
                return false;
              },
              child: CustomScrollView(slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                  sliver: SliverToBoxAdapter(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${selected.length} selected',
                              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7)),
                          const SizedBox(height: 5),
                          const Text('Choose what you want to do with these files.',
                              style: TextStyle(color: AppColors.muted, fontSize: 13)),
                        ]),
                      ),
                      TextButton(
                          onPressed: g.selectAll,
                          child: Text(selected.length == g.items.length ? 'Clear' : 'Select all',
                              style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                  ),
                ),
                if (api != null)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .82),
                      itemCount: g.items.length,
                      itemBuilder: (_, i) {
                        final m = g.items[i];
                        return MediaTile(
                          key: ValueKey(m.id),
                          item: m,
                          api: api,
                          selectable: true,
                          selected: g.selected.contains(m.id),
                          onTap: () => g.toggleSelected(m.id),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ]),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SurfaceCard(
            child: _busy
                ? const SizedBox(height: 44, child: Center(child: CircularProgressIndicator()))
                : Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _ActionIcon(Icons.download_outlined, 'Download', enabled: selected.isNotEmpty && canDownload, onTap: () {
                      context.read<DownloadManager>().addMedia(selected);
                      showToast(context, 'Saving ${selected.length} original${selected.length == 1 ? '' : 's'} to your gallery');
                      Navigator.pop(context);
                    }),
                    _ActionIcon(Icons.share_outlined, 'Share',
                        enabled: selected.isNotEmpty && canDownload && api != null,
                        onTap: () => _run(() async {
                              if (selected.length > ShareService.maxItems) {
                                showToast(context, 'Share up to ${ShareService.maxItems} at a time, or use ZIP.');
                                return;
                              }
                              await ShareService(api!, hostSessionDir: s.isHost ? s.host?.sessionDir : null).share(selected);
                            })),
                    _ActionIcon(Icons.folder_zip_outlined, 'ZIP', enabled: selected.length > 1 && canDownload, onTap: () {
                      final name = '${s.session?.name ?? 'LocalDrop'} (${selected.length} items).zip';
                      context.read<DownloadManager>().addExport(selected.map((m) => m.id).toList(), name);
                      showToast(context, 'Creating ZIP — see progress in Uploads › Downloads');
                      Navigator.pop(context);
                    }),
                    _ActionIcon(Icons.delete_outline, 'Delete',
                        enabled: selected.any(g.canDelete),
                        onTap: () => _run(() async {
                              final mine = selected.where(g.canDelete).length;
                              final ok = await confirmDialog(context,
                                  title: 'Delete $mine item${mine == 1 ? '' : 's'}?',
                                  message: 'They will be removed from the shared gallery for everyone. '
                                      '${mine < selected.length ? 'Items shared by others will be skipped. ' : ''}This cannot be undone.',
                                  confirm: 'Delete',
                                  destructive: true);
                              if (!ok) return;
                              final (deleted, skipped, failed) = await g.delete(selected);
                              if (!context.mounted) return;
                              showToast(
                                  context,
                                  failed > 0
                                      ? '$failed item(s) could not be deleted'
                                      : 'Deleted $deleted${skipped > 0 ? ' · skipped $skipped from others' : ''}',
                                  error: failed > 0);
                            })),
                  ]),
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionIcon(this.icon, this.label, {required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : .4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}
