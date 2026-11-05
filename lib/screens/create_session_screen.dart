import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_controller.dart';
import '../services/preferences.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'starting_screen.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});
  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _form = GlobalKey<FormState>();
  final _session = TextEditingController();
  final _name = TextEditingController();
  bool _approval = false;
  bool _checking = true;
  bool _iosHelp = Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _check();
    context.read<Preferences>().lastName().then((n) {
      if (mounted && n != null && _name.text.isEmpty) _name.text = n;
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await context.read<SessionController>().checkNetwork();
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _session.dispose();
    _name.dispose();
    super.dispose();
  }

  String? _validate(String? v, String what, int max) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter $what';
    if (t.length > max) return 'Keep it under $max characters';
    return null;
  }

  void _create() {
    if (!_form.currentState!.validate()) return;
    final s = context.read<SessionController>();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const StartingScreen()));
    s.createSession(sessionName: _session.text.trim(), hostName: _name.text.trim(), requireApproval: _approval);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    return AppFrame(
      child: PageShell(
        title: 'Create session',
        subtitle: 'Set up a private space for your group.',
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('Session name'),
            TextFormField(
              key: const Key('sessionName'),
              controller: _session,
              textInputAction: TextInputAction.next,
              maxLength: 60,
              validator: (v) => _validate(v, 'a session name', 60),
              decoration: const InputDecoration(hintText: 'e.g. Manali Trip 2026', prefixIcon: Icon(Icons.landscape_outlined), counterText: ''),
            ),
            const SizedBox(height: 18),
            const FieldLabel('Your name'),
            TextFormField(
              key: const Key('hostName'),
              controller: _name,
              textInputAction: TextInputAction.done,
              maxLength: 40,
              validator: (v) => _validate(v, 'your name', 40),
              onFieldSubmitted: (_) => _create(),
              decoration: const InputDecoration(hintText: 'Enter your name', prefixIcon: Icon(Icons.person_outline), counterText: ''),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _approval,
              onChanged: (v) => setState(() => _approval = v),
              title: const Text('Approve people before they join', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              subtitle: const Text('Anyone with the PIN can join when off.', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Expanded(child: Text('Before we start', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              Pill('Android', selected: !_iosHelp, onTap: () => setState(() => _iosHelp = false)),
              const SizedBox(width: 6),
              Pill('iPhone', selected: _iosHelp, onTap: () => setState(() => _iosHelp = true)),
            ]),
            const SizedBox(height: 14),
            NumberedStep(
              number: '1',
              title: 'Turn on your mobile hotspot',
              detail: _iosHelp
                  ? 'Open Settings › Personal Hotspot and turn on “Allow Others to Join”. Keep that screen open until friends connect.'
                  : 'Open Settings › Network & internet › Hotspot & tethering › Wi-Fi hotspot and switch it on. Mobile data can stay off.',
            ),
            const NumberedStep(
                number: '2', title: 'Ask friends to connect', detail: 'Share your hotspot password with everyone in the group.'),
            const NumberedStep(number: '3', title: 'Come back and create', detail: 'LocalDrop will prepare your private sharing space.'),
            _NetworkStatus(checking: _checking, interfaces: s.interfaces, onRecheck: _check),
            const SizedBox(height: 22),
            PrimaryButton(label: 'Create Session', icon: Icons.arrow_forward_rounded, onPressed: _create),
          ]),
        ),
      ),
    );
  }
}

class _NetworkStatus extends StatelessWidget {
  final bool checking;
  final List<NetworkInterfaceInfo> interfaces;
  final VoidCallback onRecheck;
  const _NetworkStatus({required this.checking, required this.interfaces, required this.onRecheck});

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 10),
        Text('Checking your network…', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      ]);
    }
    final usable = interfaces.where((i) => i.usable).toList();
    if (usable.isEmpty) {
      return InfoBanner(
        'No hotspot or Wi-Fi network detected. Turn on your hotspot (or join the same Wi-Fi as your friends). '
        'You can still create the session — the join address appears as soon as a network is available.',
        icon: Icons.wifi_off_rounded,
        action: 'Re-check',
        onAction: onRecheck,
      );
    }
    final best = usable.first;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: const Color(0xFFEAF8F2), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.check_circle, color: AppColors.green, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '${best.kind == 'hotspot' ? 'Hotspot' : best.kind == 'wifi' ? 'Wi-Fi' : 'Network'} ready · ${best.ip}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.green),
          ),
        ),
        GestureDetector(onTap: onRecheck, child: const Icon(Icons.refresh, size: 18, color: AppColors.green)),
      ]),
    );
  }
}
