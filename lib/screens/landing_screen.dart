import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_controller.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'create_session_screen.dart';
import 'join_session_screen.dart';
import 'starting_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final resumable = s.resumableHostSession;
    return AppFrame(
      showBack: false,
      child: PageShell(
        title: 'Share moments.\nKeep every detail.',
        subtitle: 'Original-quality photo and video sharing, right nearby.',
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            height: 205,
            width: double.infinity,
            decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(28)),
            child: Stack(alignment: Alignment.center, children: [
              Positioned(left: 25, top: 40, width: 130, height: 115, child: Transform.rotate(angle: -.13, child: const PhotoTile(index: 1))),
              Positioned(right: 25, top: 32, width: 130, height: 115, child: Transform.rotate(angle: .12, child: const PhotoTile(index: 2))),
              Positioned(
                  width: 150,
                  height: 125,
                  child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: const [BoxShadow(color: Color(0x223A267A), blurRadius: 15)]),
                      child: const PhotoTile(index: 3))),
              const Positioned(bottom: 12, child: Icon(Icons.wifi, color: AppColors.primary, size: 30)),
            ]),
          ),
          if (resumable != null) ...[
            const SizedBox(height: 18),
            SurfaceCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.history, color: AppColors.primary),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Text('Resume “${resumable.name}”?', style: const TextStyle(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 6),
                Text(
                  'Your session stopped unexpectedly. ${resumable.photos} photos, ${resumable.videos} videos '
                  '(${formatBytes(resumable.bytes)}) are safe on this device. Participants can reconnect with the same PIN.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const StartingScreen()));
                        s.createSession(sessionName: resumable.name, hostName: '', resumeId: resumable.id);
                      },
                      child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => s.forgetHostSession(resumable.id, deleteData: false),
                    child: const Text('Dismiss'),
                  ),
                ]),
              ]),
            ),
          ],
          const SizedBox(height: 25),
          const _Benefit(icon: Icons.high_quality_outlined, title: 'Original quality', detail: 'No compression. Ever.'),
          const _Benefit(icon: Icons.wifi_off_rounded, title: 'Works offline', detail: 'No internet or cloud required.'),
          const _Benefit(icon: Icons.groups_2_outlined, title: 'Simple & private', detail: 'Just your group, sharing together.'),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Create Session',
            icon: Icons.add,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSessionScreen())),
          ),
          const SizedBox(height: 10),
          OutlineAction(
            label: 'Join Session',
            icon: Icons.qr_code_scanner,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinSessionScreen())),
          ),
        ]),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _Benefit({required this.icon, required this.title, required this.detail});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: AppColors.primary)),
          const SizedBox(width: 13),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ])),
        ]),
      );
}
