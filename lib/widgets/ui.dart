import 'package:flutter/material.dart';
import '../theme.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  const PrimaryButton({super.key, required this.label, this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton.icon(
      onPressed: null,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 19),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.primary,
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

class OutlineAction extends StatelessWidget {
  final String label;
  final IconData icon;
  const OutlineAction({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icon, size: 18, color: AppColors.primary),
      label: Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
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
      boxShadow: [BoxShadow(color: const Color(0xFF39266F).withOpacity(.035), blurRadius: 18, offset: const Offset(0, 7))],
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      if (trailing != null) Text(trailing!, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
    ],
  );
}

class Pill extends StatelessWidget {
  final String text;
  final bool selected;
  const Pill(this.text, {super.key, this.selected = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
    decoration: BoxDecoration(
      color: selected ? AppColors.primary : const Color(0xFFF0EDFA),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(text, style: TextStyle(color: selected ? Colors.white : AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
  );
}

class Avatar extends StatelessWidget {
  final String initials;
  final Color color;
  final String? label;
  const Avatar(this.initials, {super.key, this.color = AppColors.lavender, this.label});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(radius: 19, backgroundColor: color, child: Text(initials, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800))),
      if (label != null) ...[
        const SizedBox(height: 5),
        Text(label!, style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
      ]
    ],
  );
}

class PhotoTile extends StatelessWidget {
  final int index;
  final double? height;
  final bool video;
  const PhotoTile({super.key, required this.index, this.height, this.video = false});

  static const urls = [
    'photo-1500530855697-b586d89ba3ee',
    'photo-1464822759023-fed622ff2c3b',
    'photo-1470770841072-f978cf4d019e',
    'photo-1501785888041-af3ef285b470',
    'photo-1518837695005-2083093ee35b',
    'photo-1472396961693-142e6e269027',
    'photo-1500534623283-312aаде485b7',
    'photo-1469474968028-56623f02e42e',
  ];

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(13),
    child: Stack(fit: StackFit.expand, children: [
      Image.network(
        'https://images.unsplash.com/${urls[index % urls.length]}?auto=format&fit=crop&w=700&q=85',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: const Color(0xFFDCD6F5), child: const Icon(Icons.landscape, color: AppColors.primary)),
      ),
      if (video) const Center(child: CircleAvatar(backgroundColor: Color(0x99000000), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28))),
    ]),
  );
}
