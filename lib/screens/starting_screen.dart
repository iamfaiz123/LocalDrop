import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'host_lobby_screen.dart';

/// Shows the real start-up steps reported by [SessionController.createSession].
class StartingScreen extends StatefulWidget {
  const StartingScreen({super.key});
  @override
  State<StartingScreen> createState() => _StartingScreenState();
}

class _StartingScreenState extends State<StartingScreen> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    if (!_navigated && s.phase == SessionPhase.active && s.isHost) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HostLobbyScreen(firstRun: true)),
          (_) => false,
        );
      });
    }
    final failed = s.steps.any((x) => x.state == StartStepState.failed);
    return AppFrame(
      showBack: failed,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                  color: failed ? const Color(0xFFFFF1F1) : AppColors.lavender,
                  shape: BoxShape.circle,
                  border: Border.all(color: failed ? const Color(0xFFFFD2D5) : const Color(0xFFD8CCFF), width: 9)),
              child: Icon(failed ? Icons.wifi_off_rounded : Icons.wifi, color: failed ? AppColors.red : AppColors.primary, size: 65),
            ),
            const SizedBox(height: 28),
            Text(failed ? 'Couldn’t start your session' : 'Starting your session…',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 28),
            for (final step in s.steps) ProgressStepRow(step),
            if (failed) ...[
              const SizedBox(height: 22),
              PrimaryButton(label: 'Go back', icon: Icons.arrow_back, onPressed: () => Navigator.maybePop(context)),
            ],
          ]),
        ),
      ),
    );
  }
}
