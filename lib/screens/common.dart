import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_controller.dart';
import '../services/realtime_service.dart';
import '../theme.dart';

/// Top bar from the original design: logo, wordmark and a status chip.
class AppHeader extends StatelessWidget {
  final Widget? leading;
  final List<Widget> actions;
  const AppHeader({super.key, this.leading, this.actions = const []});

  @override
  Widget build(BuildContext context) => Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: AppColors.bg,
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          const Icon(Icons.cloud_outlined, color: AppColors.primary, size: 27),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('LocalDrop', maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          ),
          ...actions,
          const ConnectionChip(),
        ]),
      );
}

/// Replaces the prototype's "UI PREVIEW" chip with live connection state.
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final (String label, Color dot) = switch (s.phase) {
      SessionPhase.active => switch (s.connection) {
          ConnectionStatus.connected => (s.isHost ? 'HOSTING' : 'CONNECTED', AppColors.green),
          ConnectionStatus.closed => ('OFFLINE', AppColors.red),
          _ => ('RECONNECTING', const Color(0xFFE0A100)),
        },
      SessionPhase.pending => ('WAITING', const Color(0xFFE0A100)),
      _ => ('OFFLINE MODE', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: .8)),
      ]),
    );
  }
}

/// Full-screen page with the LocalDrop header (outside an active session).
class AppFrame extends StatelessWidget {
  final Widget child;
  final bool showBack;
  const AppFrame({super.key, required this.child, this.showBack = true});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            AppHeader(
              leading: showBack && Navigator.canPop(context)
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.maybePop(context),
                    )
                  : null,
            ),
            Expanded(child: child),
          ]),
        ),
      );
}

class PageShell extends StatelessWidget {
  final String title;
  final Widget child;
  final String? subtitle;
  final Widget? trailing;
  final ScrollController? controller;
  final Future<void> Function()? onRefresh;
  const PageShell({super.key, required this.title, required this.child, this.subtitle, this.trailing, this.controller, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scroll = SingleChildScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7)),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 22),
        child,
      ]),
    );
    return onRefresh == null ? scroll : RefreshIndicator(onRefresh: onRefresh!, color: AppColors.primary, child: scroll);
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)));
}

class NumberedStep extends StatelessWidget {
  final String number, title, detail;
  const NumberedStep({super.key, required this.number, required this.title, required this.detail});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.lavender,
            child: Text(number, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900))),
        const SizedBox(width: 13),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
        ])),
      ]));
}

class ProgressStepRow extends StatelessWidget {
  final StartStep step;
  const ProgressStepRow(this.step, {super.key});
  @override
  Widget build(BuildContext context) {
    final icon = switch (step.state) {
      StartStepState.done => const Icon(Icons.check_circle, color: AppColors.green),
      StartStepState.warning => const Icon(Icons.error_outline, color: Color(0xFFE0A100)),
      StartStepState.failed => const Icon(Icons.cancel, color: AppColors.red),
      StartStepState.running =>
        const SizedBox(width: 24, height: 24, child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.5))),
      StartStepState.pending => const Icon(Icons.radio_button_unchecked, color: AppColors.primary),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(step.label, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (step.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(step.detail!,
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: step.state == StartStepState.failed ? AppColors.red : AppColors.muted)),
              ),
          ]),
        ),
      ]),
    );
  }
}
