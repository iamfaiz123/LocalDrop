import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_controller.dart';
import '../services/ads.dart';
import '../theme.dart';
import '../widgets/ad_banner.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'create_session_screen.dart';
import 'join_session_screen.dart';
import 'session_shell.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    return AppFrame(
      showBack: false,
      bottom: const AdBanner(),
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
          const SizedBox(height: 25),
          const _Benefit(icon: Icons.high_quality_outlined, title: 'Original quality', detail: 'No compression. Ever.'),
          const _Benefit(icon: Icons.wifi_off_rounded, title: 'Works offline', detail: 'No internet or cloud required.'),
          const _Benefit(icon: Icons.groups_2_outlined, title: 'Simple & private', detail: 'Just your group, sharing together.'),
          const SizedBox(height: 22),
          if (s.hasSession)
            _ActiveSessionCard(controller: s)
          else ...[
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
          ],
          if (context.watch<AdService>().privacyOptionsRequired)
            TextButton(
              onPressed: () => context.read<AdService>().showPrivacyOptions(),
              child: const Text('Ad privacy settings', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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

/// Shown instead of Create/Join while this device belongs to a session.
/// Only one session at a time: it must be ended (host) or left (participant).
class _ActiveSessionCard extends StatefulWidget {
  final SessionController controller;
  const _ActiveSessionCard({required this.controller});
  @override
  State<_ActiveSessionCard> createState() => _ActiveSessionCardState();
}

class _ActiveSessionCardState extends State<_ActiveSessionCard> {
  bool _busy = false;

  Future<void> _open() async {
    final s = widget.controller;
    var ok = s.phase == SessionPhase.active;
    if (!ok) {
      setState(() => _busy = true);
      ok = await s.restore();
      if (mounted) setState(() => _busy = false);
    }
    if (ok && mounted) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SessionShell()), (_) => false);
    }
  }

  Future<void> _end() async {
    final s = widget.controller;
    final host = (s.locked?.role ?? s.role) == SessionRole.host;
    final ok = await confirmDialog(
      context,
      title: host ? 'End this session?' : 'Leave this session?',
      message: host
          ? 'Everyone is disconnected. Shared media stays on this phone.'
          : 'You can rejoin later with the PIN.',
      confirm: host ? 'End Session' : 'Leave',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      if (s.phase == SessionPhase.pending) {
        await s.cancelPending();
      } else {
        await s.endLockedSession();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller;
    final l = s.locked;
    final host = (l?.role ?? s.role) == SessionRole.host;
    final name = l?.name ?? s.session?.name ?? 'your session';
    final detail = l?.reason ??
        (s.phase == SessionPhase.pending
            ? 'Waiting for the host to let you in.'
            : s.phase == SessionPhase.starting
                ? 'Starting…'
                : host
                    ? 'Your session is running. Friends can keep sharing.'
                    : 'You are connected to this session.');
    return SurfaceCard(
      key: const Key('activeSession'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(host ? Icons.wifi_tethering : Icons.groups_rounded, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(host ? 'You are hosting “$name”' : 'You are in “$name”',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
        const SizedBox(height: 6),
        Text(
          host ? 'End this session to create or join another one.' : 'Leave this session to create or join another one.',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: l == null ? 'Open session' : 'Reconnect',
          icon: Icons.arrow_forward_rounded,
          loading: _busy,
          onPressed: s.phase == SessionPhase.pending || s.phase == SessionPhase.starting ? null : _open,
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _end,
            child: Text(host ? 'End session' : 'Leave session',
                style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
