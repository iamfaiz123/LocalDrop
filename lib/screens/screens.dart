import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class PageShell extends StatelessWidget {
  final String title;
  final Widget child;
  final String? subtitle;
  const PageShell({super.key, required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7)),
      if (subtitle != null) ...[const SizedBox(height: 5), Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 13))],
      const SizedBox(height: 22),
      child,
    ]),
  );
}

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(
    title: 'Share moments.\\nKeep every detail.',
    subtitle: 'Original-quality photo and video sharing, right nearby.',
    child: Column(children: [
      const SizedBox(height: 10),
      Container(
        height: 205, width: double.infinity,
        decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(28)),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(left: 25, top: 40, width: 130, height: 115, child: Transform.rotate(angle: -.13, child: const PhotoTile(index: 1))),
          Positioned(right: 25, top: 32, width: 130, height: 115, child: Transform.rotate(angle: .12, child: const PhotoTile(index: 2))),
          Positioned(width: 150, height: 125, child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), boxShadow: const [BoxShadow(color: Color(0x223A267A), blurRadius: 15)]), child: const PhotoTile(index: 3))),
          const Positioned(bottom: 12, child: Icon(Icons.wifi, color: AppColors.primary, size: 30)),
        ]),
      ),
      const SizedBox(height: 25),
      const _Benefit(icon: Icons.high_quality_outlined, title: 'Original quality', detail: 'No compression. Ever.'),
      const _Benefit(icon: Icons.wifi_off_rounded, title: 'Works offline', detail: 'No internet or cloud required.'),
      const _Benefit(icon: Icons.groups_2_outlined, title: 'Simple & private', detail: 'Just your group, sharing together.'),
      const SizedBox(height: 22),
      const PrimaryButton(label: 'Create Session', icon: Icons.add),
      const SizedBox(height: 10),
      const OutlineAction(label: 'Join Session', icon: Icons.qr_code_scanner),
    ]),
  );
}

class _Benefit extends StatelessWidget {
  final IconData icon; final String title; final String detail;
  const _Benefit({required this.icon, required this.title, required this.detail});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: AppColors.primary)),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ])),
    ]),
  );
}

class CreateSessionScreen extends StatelessWidget {
  const CreateSessionScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Create session', subtitle: 'Set up a private space for your group.',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _FieldLabel('Session name'),
      const TextField(decoration: InputDecoration(hintText: 'e.g. Manali Trip 2026', prefixIcon: Icon(Icons.landscape_outlined))),
      const SizedBox(height: 18),
      const _FieldLabel('Your name'),
      const TextField(decoration: InputDecoration(hintText: 'Enter your name', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 25),
      const Text('Before we start', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      const _Step(number: '1', title: 'Turn on your mobile hotspot', detail: 'Open your phone settings and enable Personal Hotspot or Mobile Hotspot.'),
      const _Step(number: '2', title: 'Ask friends to connect', detail: 'Share your hotspot password with everyone in the group.'),
      const _Step(number: '3', title: 'Come back and create', detail: 'LocalDrop will prepare your private sharing space.'),
      const SizedBox(height: 22),
      const PrimaryButton(label: 'Create Session', icon: Icons.arrow_forward_rounded),
    ]),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text; const _FieldLabel(this.text);
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)));
}
class _Step extends StatelessWidget {
  final String number, title, detail; const _Step({required this.number, required this.title, required this.detail});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 17), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    CircleAvatar(radius: 16, backgroundColor: AppColors.lavender, child: Text(number, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900))),
    const SizedBox(width: 13),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45))])),
  ]));
}

class StartingScreen extends StatelessWidget {
  const StartingScreen({super.key});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 150, height: 150, decoration: BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFD8CCFF), width: 9)), child: const Icon(Icons.wifi, color: AppColors.primary, size: 65)),
    const SizedBox(height: 28),
    const Text('Starting your session…', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
    const SizedBox(height: 28),
    const _StatusRow('Checking network', true),
    const _StatusRow('Starting local server', true),
    const _StatusRow('Preparing gallery', false),
  ])));
}
class _StatusRow extends StatelessWidget {
  final String label; final bool complete; const _StatusRow(this.label, this.complete);
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
    Icon(complete ? Icons.check_circle : Icons.radio_button_unchecked, color: complete ? AppColors.green : AppColors.primary),
    const SizedBox(width: 12), Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  ]));
}

class HostLobbyScreen extends StatelessWidget {
  const HostLobbyScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Manali Trip 2026', subtitle: 'You are the host · Session is ready',
    child: Column(children: [
      SurfaceCard(child: Column(children: [
        const Text('Scan to join', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(width: 190, height: 190, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)), child: const Icon(Icons.qr_code_2, size: 160, color: AppColors.text)),
        const SizedBox(height: 15),
        const Text('SESSION PIN', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 5),
        const Text('8 3 7 2', style: TextStyle(fontSize: 26, letterSpacing: 5, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.link, color: AppColors.primary), SizedBox(width: 8), Expanded(child: Text('http://192.168.43.1:8080', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))), Icon(Icons.copy, size: 17)])),
      ])),
      const SizedBox(height: 20),
      const SectionTitle('4 members', trailing: 'Manage'),
      const SizedBox(height: 16),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Avatar('A', label: 'Aarav · Host'), Avatar('R', color: Color(0xFFDDF5FF), label: 'Riya'), Avatar('K', color: Color(0xFFFFE9C8), label: 'Karan'), Avatar('M', color: Color(0xFFF1DFFF), label: 'Meera')]),
      const SizedBox(height: 20),
      const PrimaryButton(label: 'Open shared gallery', icon: Icons.photo_library_outlined),
    ]),
  );
}

class JoinSessionScreen extends StatelessWidget {
  const JoinSessionScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Join session', subtitle: 'Scan your friend’s QR code to join.',
    child: Column(children: [
      const Row(children: [Pill('Scan QR', selected: true), SizedBox(width: 8), Pill('Enter address')]),
      const SizedBox(height: 20),
      Container(height: 310, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF242333), borderRadius: BorderRadius.circular(24)), child: Stack(alignment: Alignment.center, children: [
        const Icon(Icons.qr_code_2, size: 170, color: Colors.white24),
        Container(width: 210, height: 210, decoration: BoxDecoration(border: Border.all(color: AppColors.primary, width: 4), borderRadius: BorderRadius.circular(24))),
        const Positioned(bottom: 23, child: Text('Align the QR code within the frame', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
      ])),
      const SizedBox(height: 18),
      const Text('Or enter the session address manually', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 10),
      const TextField(decoration: InputDecoration(hintText: 'http://192.168.x.x:8080', prefixIcon: Icon(Icons.link))),
    ]),
  );
}

class JoinDetailsScreen extends StatelessWidget {
  const JoinDetailsScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Join session', subtitle: 'You’re almost there.',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 76, height: 76, decoration: const BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle), child: const Icon(Icons.groups_rounded, color: AppColors.primary, size: 38))),
      const SizedBox(height: 17),
      const Center(child: Text('Manali Trip 2026', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
      const Center(child: Text('Enter your details to join', style: TextStyle(color: AppColors.muted, fontSize: 12))),
      const SizedBox(height: 28),
      const _FieldLabel('Your name'),
      const TextField(decoration: InputDecoration(hintText: 'Riya', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 18),
      const _FieldLabel('Session PIN'),
      const TextField(decoration: InputDecoration(hintText: '• • • •', prefixIcon: Icon(Icons.lock_outline))),
      const SizedBox(height: 25),
      const PrimaryButton(label: 'Join Session', icon: Icons.arrow_forward_rounded),
    ]),
  );
}

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Manali Trip 2026', subtitle: '4 members · 248 items',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Pill('All', selected: true), SizedBox(width: 7), Pill('Photos'), SizedBox(width: 7), Pill('Videos')]),
      const SizedBox(height: 22),
      const SectionTitle('Today', trailing: 'Newest first'),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: 12, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .82),
        itemBuilder: (_, i) => PhotoTile(index: i, video: i == 5 || i == 8 || i == 10),
      ),
      const SizedBox(height: 20),
      const PrimaryButton(label: 'Upload photos & videos', icon: Icons.add),
    ]),
  );
}

class MediaViewerScreen extends StatelessWidget {
  const MediaViewerScreen({super.key});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF11121A),
    child: Column(children: [
      const Padding(padding: EdgeInsets.all(18), child: Row(children: [Icon(Icons.arrow_back, color: Colors.white), Spacer(), Text('2 of 248', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)), Spacer(), Icon(Icons.more_vert, color: Colors.white)])),
      const Expanded(child: Padding(padding: EdgeInsets.symmetric(vertical: 15), child: PhotoTile(index: 1))),
      const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 20), child: Row(children: [
        CircleAvatar(radius: 16, child: Text('K')), SizedBox(width: 9),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Karan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), Text('Today, 10:24 AM', style: TextStyle(color: Colors.white70, fontSize: 11))]),
        Spacer(), Icon(Icons.share_outlined, color: Colors.white), SizedBox(width: 24), Icon(Icons.download_outlined, color: Colors.white), SizedBox(width: 24), Icon(Icons.favorite_border, color: Colors.white),
      ])),
    ]),
  );
}

class UploadsScreen extends StatelessWidget {
  const UploadsScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Uploads', subtitle: 'Manage your transfers.',
    child: Column(children: [
      const Row(children: [Pill('Uploading (3)', selected: true), SizedBox(width: 8), Pill('Completed')]),
      const SizedBox(height: 20),
      const _UploadRow(name: 'IMG_4829.JPG', detail: '24 MB · 12.4 MB/s', progress: .72, percent: '72%', index: 1),
      const _UploadRow(name: 'VID_0193.MP4', detail: '1.2 GB · 9.8 MB/s', progress: .34, percent: '34%', index: 2),
      const _UploadRow(name: 'IMG_4830.JPG', detail: '18 MB · Waiting…', progress: .03, percent: 'Queued', index: 3),
      const SizedBox(height: 20),
      const OutlineAction(label: 'Add more files', icon: Icons.add),
    ]),
  );
}
class _UploadRow extends StatelessWidget {
  final String name, detail, percent; final double progress; final int index;
  const _UploadRow({required this.name, required this.detail, required this.progress, required this.percent, required this.index});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Row(children: [
    SizedBox(width: 65, height: 65, child: PhotoTile(index: index)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      const SizedBox(height: 8),
      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: AppColors.lavender, color: AppColors.primary)),
    ])),
    const SizedBox(width: 9),
    Text(percent, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10)),
  ]));
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Session dashboard', subtitle: 'A quick overview of your group’s activity.',
    child: Column(children: [
      Row(children: [
        Expanded(child: _StatCard(icon: Icons.photo_outlined, value: '248', label: 'Photos')),
        const SizedBox(width: 9),
        Expanded(child: _StatCard(icon: Icons.videocam_outlined, value: '32', label: 'Videos')),
        const SizedBox(width: 9),
        Expanded(child: _StatCard(icon: Icons.storage_outlined, value: '12.4 GB', label: 'Total')),
      ]),
      const SizedBox(height: 22),
      const SectionTitle('Participants', trailing: 'Manage'),
      const SizedBox(height: 12),
      const _MemberRow('A', 'Aarav (Host)', '2.8 GB · 86 items'),
      const _MemberRow('R', 'Riya', '3.1 GB · 72 items'),
      const _MemberRow('K', 'Karan', '4.2 GB · 89 items'),
      const _MemberRow('M', 'Meera', '2.3 GB · 33 items'),
      const SizedBox(height: 22),
      const SectionTitle('Storage on this device'),
      const SizedBox(height: 12),
      const SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Used by session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Text('12.4 GB', style: TextStyle(fontWeight: FontWeight.w900))]),
        SizedBox(height: 12),
        LinearProgressIndicator(value: .38, minHeight: 8, backgroundColor: AppColors.lavender, color: AppColors.primary),
        SizedBox(height: 9),
        Text('86.4 GB free of 128 GB', style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ])),
    ]),
  );
}
class _StatCard extends StatelessWidget {
  final IconData icon; final String value, label;
  const _StatCard({required this.icon, required this.value, required this.label});
  @override Widget build(BuildContext context) => SurfaceCard(padding: const EdgeInsets.all(12), child: Column(children: [
    Icon(icon, color: AppColors.primary), const SizedBox(height: 8),
    Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
  ]));
}
class _MemberRow extends StatelessWidget {
  final String initial, name, detail;
  const _MemberRow(this.initial, this.name, this.detail);
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(children: [
    Avatar(initial), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)), Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 10))])),
    const Icon(Icons.more_horiz, color: AppColors.muted),
  ]));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: 'Session settings', subtitle: 'Manage access and session preferences.',
    child: Column(children: [
      const SurfaceCard(child: Column(children: [
        _SettingRow(Icons.edit_outlined, 'Session name', 'Manali Trip 2026'),
        Divider(color: AppColors.border),
        _SettingRow(Icons.cloud_upload_outlined, 'Upload permission', 'Everyone can upload'),
        Divider(color: AppColors.border),
        _SettingRow(Icons.download_outlined, 'Download permission', 'Everyone can download'),
      ])),
      const SizedBox(height: 15),
      const SurfaceCard(child: Column(children: [
        _SettingRow(Icons.groups_outlined, 'Manage participants', 'View, remove or block members'),
        Divider(color: AppColors.border),
        _SettingRow(Icons.delete_outline, 'Delete media', 'Remove photos and videos'),
      ])),
      const SizedBox(height: 22),
      Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFFFD2D5))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.power_settings_new, color: AppColors.red), SizedBox(width: 9), Text('End Session', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900))])),
    ]),
  );
}
class _SettingRow extends StatelessWidget {
  final IconData icon; final String title, detail;
  const _SettingRow(this.icon, this.title, this.detail);
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
    Icon(icon, color: AppColors.primary), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)), Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 10))])),
    const Icon(Icons.chevron_right, color: AppColors.muted),
  ]));
}

class SelectionScreen extends StatelessWidget {
  const SelectionScreen({super.key});
  @override
  Widget build(BuildContext context) => PageShell(title: '5 selected', subtitle: 'Choose what you want to do with these files.',
    child: Column(children: [
      GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: 9, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .82), itemBuilder: (_, i) => Stack(children: [
        Positioned.fill(child: PhotoTile(index: i, video: i == 5)),
        Positioned(right: 7, top: 7, child: CircleAvatar(radius: 11, backgroundColor: AppColors.primary, child: const Icon(Icons.check, color: Colors.white, size: 14))),
      ])),
      const SizedBox(height: 20),
      SurfaceCard(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const [
        _ActionIcon(Icons.download_outlined, 'Download'),
        _ActionIcon(Icons.share_outlined, 'Share'),
        _ActionIcon(Icons.delete_outline, 'Delete'),
      ])),
    ]),
  );
}
class _ActionIcon extends StatelessWidget {
  final IconData icon; final String label;
  const _ActionIcon(this.icon, this.label);
  @override Widget build(BuildContext context) => Column(children: [Icon(icon, color: AppColors.primary), const SizedBox(height: 6), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]);
}
