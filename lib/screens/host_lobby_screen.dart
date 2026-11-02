import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/session_controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'participants_sheet.dart';
import 'session_shell.dart';

/// QR code, PIN, server address and members — the host's invite screen.
class HostLobbyScreen extends StatelessWidget {
  final bool firstRun;
  const HostLobbyScreen({super.key, this.firstRun = false});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    if (s.phase != SessionPhase.active) {
      return const AppFrame(child: Center(child: CircularProgressIndicator()));
    }
    final info = s.session!;
    final pin = info.pin ?? s.host?.pin ?? '';
    final url = s.hostUrls.isNotEmpty ? s.hostUrls.first : null;
    final members = s.participants.where((p) => p.isActive).toList();
    final pending = s.pendingRequests;

    final body = PageShell(
      title: info.name,
      subtitle: 'You are the host · ${s.networkOk ? 'Session is ready' : 'Waiting for a network'}',
      child: Column(children: [
        if (!s.networkOk) ...[
          const InfoBanner(
            'No hotspot or Wi-Fi detected. Turn on your mobile hotspot — the QR code appears automatically.',
            icon: Icons.wifi_off_rounded,
          ),
          const SizedBox(height: 14),
        ],
        SurfaceCard(
          child: Column(children: [
            const Text('Scan to join', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Container(
              width: 190,
              height: 190,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: s.joinUrl == null
                  ? const Icon(Icons.qr_code_2, size: 160, color: AppColors.border)
                  : QrImageView(
                      key: const Key('joinQr'),
                      data: s.joinUrl!,
                      padding: EdgeInsets.zero,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.text),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.text),
                    ),
            ),
            const SizedBox(height: 15),
            const Text('SESSION PIN', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            const SizedBox(height: 5),
            SelectableText(pin.split('').join(' '),
                key: const Key('pin'), style: const TextStyle(fontSize: 26, letterSpacing: 5, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: url == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: url));
                      showToast(context, 'Address copied');
                    },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.link, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(url ?? 'Waiting for hotspot / Wi-Fi…',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                  if (url != null) const Icon(Icons.copy, size: 17),
                ]),
              ),
            ),
            if (s.hostUrls.length > 1) ...[
              const SizedBox(height: 8),
              Text('Also reachable at ${s.hostUrls.skip(1).join(', ')}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
            const SizedBox(height: 10),
            const Text(
              'Friends without the app can open the address in their browser. '
              'Transfers stay on this network and are not encrypted, so only share the PIN with your group.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppColors.muted, height: 1.4),
            ),
          ]),
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final p in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Avatar(p.initials, color: avatarColor(p.avatarColor)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${p.name} wants to join', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  TextButton(onPressed: () => s.participantAction(p.id, 'reject'), child: const Text('Deny')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    onPressed: () => s.participantAction(p.id, 'approve'),
                    child: const Text('Allow'),
                  ),
                ]),
              ),
            ),
        ],
        const SizedBox(height: 20),
        SectionTitle('${members.length} member${members.length == 1 ? '' : 's'}',
            trailing: 'Manage', onTrailing: () => showParticipantsSheet(context)),
        const SizedBox(height: 16),
        SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (_, i) {
              final p = members[i];
              return Avatar(p.initials,
                  color: avatarColor(p.avatarColor), online: p.online, label: p.isHost ? '${p.name} · Host' : p.name);
            },
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Open shared gallery',
          icon: Icons.photo_library_outlined,
          onPressed: () {
            if (firstRun) {
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SessionShell()), (_) => false);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ]),
    );
    return AppFrame(showBack: !firstRun, child: body);
  }
}
