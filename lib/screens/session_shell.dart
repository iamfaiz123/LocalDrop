import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'dashboard_screen.dart';
import 'gallery_screen.dart';
import 'host_lobby_screen.dart';
import 'landing_screen.dart';
import 'settings_screen.dart';
import 'uploads_screen.dart';

/// In-session scaffold: header + tabbed pages + bottom bar in the original
/// design's style. Also handles lifecycle (resume/reconnect) and the
/// ended/removed state.
class SessionShell extends StatefulWidget {
  const SessionShell({super.key});
  @override
  State<SessionShell> createState() => SessionShellState();
}

class SessionShellState extends State<SessionShell> with WidgetsBindingObserver {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<SessionController>().onResumed();
  }

  void select(int i) => setState(() => tab = i);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    if (s.phase == SessionPhase.ended || s.phase == SessionPhase.removed) {
      return _EndedView(controller: s);
    }
    if (s.phase != SessionPhase.active) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final names = ['Gallery', 'Uploads', 'Dashboard', s.isHost ? 'Host controls' : 'Session'];
    const pages = [GalleryScreen(), UploadsScreen(), DashboardScreen(), SettingsScreen()];
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(0);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            AppHeader(actions: [
              if (s.isHost)
                IconButton(
                  tooltip: 'Invite (QR code & PIN)',
                  icon: const Icon(Icons.qr_code_2, color: AppColors.primary),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HostLobbyScreen())),
                ),
            ]),
            if (s.storageWarning && s.isHost)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: InfoBanner('Storage is running low on this phone. Free up space or new uploads will be refused.',
                    icon: Icons.sd_card_alert_outlined),
              ),
            Expanded(child: IndexedStack(index: tab, children: pages)),
          ]),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(children: [
                for (var i = 0; i < names.length; i++)
                  Expanded(
                    child: GestureDetector(
                      key: Key('tab-$i'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => select(i),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                          decoration: BoxDecoration(
                              color: tab == i ? AppColors.lavender : Colors.transparent, borderRadius: BorderRadius.circular(13)),
                          child: _TabLabel(name: names[i], selected: tab == i, badge: i == 1 ? _transferBadge(context) : 0),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  int _transferBadge(BuildContext context) => context.select<SessionController, int>(
        (s) => s.uploads.runningCount + s.downloads.active.length,
      );
}

class _TabLabel extends StatelessWidget {
  final String name;
  final bool selected;
  final int badge;
  const _TabLabel({required this.name, required this.selected, required this.badge});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? AppColors.primaryDark : AppColors.muted)),
        ),
        if (badge > 0) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(9)),
            child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
          ),
        ],
      ]);
}

class _EndedView extends StatelessWidget {
  final SessionController controller;
  const _EndedView({required this.controller});
  @override
  Widget build(BuildContext context) {
    final removed = controller.phase == SessionPhase.removed;
    return AppFrame(
      showBack: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            StateMessage(
              icon: removed ? Icons.person_off_outlined : Icons.check_circle_outline,
              title: removed ? 'You’re no longer in this session' : 'Session ended',
              detail: controller.endedMessage,
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Back to home',
              icon: Icons.home_outlined,
              onPressed: () {
                controller.acknowledgeEnd();
                Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LandingScreen()), (_) => false);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
