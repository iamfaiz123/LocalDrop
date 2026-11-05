import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_controller.dart';
import '../services/api_client.dart';
import '../services/preferences.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'session_shell.dart';

class JoinDetailsScreen extends StatefulWidget {
  final Uri base;
  final SessionInfo info;
  const JoinDetailsScreen({super.key, required this.base, required this.info});
  @override
  State<JoinDetailsScreen> createState() => _JoinDetailsScreenState();
}

class _JoinDetailsScreenState extends State<JoinDetailsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    context.read<Preferences>().lastName().then((n) {
      if (mounted && n != null && _name.text.isEmpty) _name.text = n;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().join(widget.base, name: _name.text.trim(), pin: _pin.text.trim());
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = switch (e.code) {
              'invalid_pin' => 'That PIN is not correct. Check the host’s screen.',
              'too_many_attempts' => e.message,
              'blocked' => 'The host blocked this device from the session.',
              'session_ended' => 'This session has ended.',
              'already_in_session' => e.message,
              _ => e.message,
            });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    if (!_navigated && s.phase == SessionPhase.active && !s.isHost) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SessionShell()), (_) => false);
        }
      });
    }
    final pending = s.phase == SessionPhase.pending;
    final rejected = s.phase == SessionPhase.removed || (s.phase == SessionPhase.ended && !s.isHost);
    return AppFrame(
      child: PageShell(
        title: 'Join session',
        subtitle: 'You’re almost there.',
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle),
                    child: const Icon(Icons.groups_rounded, color: AppColors.primary, size: 38))),
            const SizedBox(height: 17),
            Center(
                child: Text(widget.info.name,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            Center(
                child: Text('Hosted by ${widget.info.hostName} · Enter your details to join',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
            const SizedBox(height: 28),
            if (pending) ...[
              const SurfaceCard(
                child: Column(children: [
                  SizedBox(height: 6),
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Waiting for the host to let you in…', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('Keep this screen open.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  SizedBox(height: 6),
                ]),
              ),
              const SizedBox(height: 16),
              OutlineAction(label: 'Cancel request', icon: Icons.close, onPressed: () => s.cancelPending()),
            ] else ...[
              if (rejected && s.endedMessage != null) ...[
                InfoBanner(s.endedMessage!, error: true),
                const SizedBox(height: 16),
              ],
              const FieldLabel('Your name'),
              TextFormField(
                key: const Key('joinName'),
                controller: _name,
                maxLength: 40,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                decoration: const InputDecoration(hintText: 'Riya', prefixIcon: Icon(Icons.person_outline), counterText: ''),
              ),
              const SizedBox(height: 18),
              const FieldLabel('Session PIN'),
              TextFormField(
                key: const Key('joinPin'),
                controller: _pin,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.info.pinLength)],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _join(),
                validator: (v) => RegExp(r'^\d{4,6}$').hasMatch((v ?? '').trim()) ? null : 'Enter the PIN shown on the host’s screen',
                decoration: InputDecoration(
                    hintText: List.filled(widget.info.pinLength, '•').join(' '), prefixIcon: const Icon(Icons.lock_outline)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                InfoBanner(_error!, error: true),
              ],
              const SizedBox(height: 25),
              PrimaryButton(label: 'Join Session', icon: Icons.arrow_forward_rounded, loading: _busy, onPressed: _join),
            ],
          ]),
        ),
      ),
    );
  }
}
