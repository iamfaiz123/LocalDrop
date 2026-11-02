import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : (icon == null ? const SizedBox.shrink() : Icon(icon, size: 19)),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: loading ? 1 : .5),
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
}

class OutlineAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const OutlineAction({super.key, required this.label, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: AppColors.primary),
          label: Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: const Color(0xFF39266F).withValues(alpha: .035), blurRadius: 18, offset: const Offset(0, 7))],
        ),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;
  const SectionTitle(this.title, {super.key, this.trailing, this.onTrailing});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailing,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(trailing!, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
        ],
      );
}

class Pill extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback? onTap;
  const Pill(this.text, {super.key, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : const Color(0xFFF0EDFA),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(text, style: TextStyle(color: selected ? Colors.white : AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );
}

class Avatar extends StatelessWidget {
  final String initials;
  final Color color;
  final String? label;
  final bool? online;
  const Avatar(this.initials, {super.key, this.color = AppColors.lavender, this.label, this.online});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(
                radius: 19,
                backgroundColor: color,
                child: Text(initials, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800))),
            if (online != null)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: online! ? AppColors.green : const Color(0xFFC9C5D8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ]),
          if (label != null) ...[
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(label!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
          ]
        ],
      );
}

Color avatarColor(int? argb) => argb == null ? AppColors.lavender : Color(argb);

/// Decorative offline artwork (used on the landing screen). No network.
class PhotoTile extends StatelessWidget {
  final int index;
  final double? height;
  final bool video;
  const PhotoTile({super.key, required this.index, this.height, this.video = false});

  static const _palettes = [
    [Color(0xFFB8A6F2), Color(0xFF6845D8)],
    [Color(0xFF9FD8F5), Color(0xFF4C8DD8)],
    [Color(0xFFFFD39A), Color(0xFFF08A5D)],
    [Color(0xFFA8E6CF), Color(0xFF3BA27A)],
    [Color(0xFFF7B2D9), Color(0xFFB1559A)],
  ];

  @override
  Widget build(BuildContext context) {
    final p = _palettes[index % _palettes.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p)),
          child: Align(
            alignment: const Alignment(0, .55),
            child: Icon(Icons.landscape_rounded, color: Colors.white.withValues(alpha: .85), size: 46),
          ),
        ),
        Positioned(right: 18, top: 16, child: CircleAvatar(radius: 9, backgroundColor: Colors.white.withValues(alpha: .8))),
        if (video) const _PlayBadge(),
      ]),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();
  @override
  Widget build(BuildContext context) => const Center(
      child: CircleAvatar(backgroundColor: Color(0x99000000), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28)));
}

/// Gallery tile backed by the engine's thumbnail endpoint. Full-resolution
/// originals are never loaded into the grid.
class MediaTile extends StatelessWidget {
  final MediaItem item;
  final ApiClient api;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const MediaTile({
    super.key,
    required this.item,
    required this.api,
    this.selectable = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = Container(
      color: const Color(0xFFDCD6F5),
      child: Icon(item.isVideo ? Icons.movie_outlined : Icons.photo_outlined, color: AppColors.primary),
    );
    return Semantics(
      button: true,
      label: '${item.isVideo ? 'Video' : 'Photo'} by ${item.uploader.name}',
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(fit: StackFit.expand, children: [
            if (item.hasThumbnail)
              Image.network(
                api.thumbnailUrl(item),
                headers: api.authHeaders,
                fit: BoxFit.cover,
                cacheWidth: (160 * dpr).round(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => placeholder,
                frameBuilder: (_, child, frame, sync) => frame == null && !sync ? placeholder : child,
              )
            else
              placeholder,
            if (selected) Container(color: Colors.white.withValues(alpha: .18)),
            if (item.isVideo) const _PlayBadge(),
            if (item.favorite)
              const Positioned(left: 7, bottom: 6, child: Icon(Icons.favorite, color: Colors.white, size: 15, shadows: [Shadow(blurRadius: 4)])),
            if (selectable)
              Positioned(
                right: 7,
                top: 7,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: selected ? AppColors.primary : Colors.black26,
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Inline banner for warnings/errors (offline, low storage, …).
class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool error;
  final String? action;
  final VoidCallback? onAction;
  const InfoBanner(this.text, {super.key, this.icon = Icons.info_outline, this.error = false, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFFF1F1) : const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: error ? const Color(0xFFFFD2D5) : const Color(0xFFFFE2A8)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: error ? AppColors.red : AppColors.amber),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w700, color: error ? AppColors.red : AppColors.amber)),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(action!, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
        ]),
      );
}

/// Centered empty / error state.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;
  const StateMessage({super.key, required this.icon, required this.title, this.detail, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primary, size: 34),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            SizedBox(width: 200, child: OutlineAction(label: action!, icon: Icons.refresh, onPressed: onAction)),
          ],
        ]),
      );
}

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: error ? AppColors.red : AppColors.text,
      duration: Duration(seconds: error ? 5 : 3),
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      content: Text(message, style: const TextStyle(color: AppColors.muted, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm, style: TextStyle(color: destructive ? AppColors.red : AppColors.primary, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}
