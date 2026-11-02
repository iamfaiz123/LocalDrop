import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_controller.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';

Future<void> showParticipantsSheet(BuildContext context) {
  context.read<SessionController>().refreshParticipants();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _ParticipantsSheet(),
  );
}

class _ParticipantsSheet extends StatelessWidget {
  const _ParticipantsSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final people = [...s.participants]..sort((a, b) => _rank(a).compareTo(_rank(b)));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Center(
              child: Container(
                  width: 42, height: 5, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 16),
          const Text('Participants', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(s.isHost ? 'Approve, remove or block members.' : 'People in this session.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 14),
          for (final p in people) _ParticipantTile(p: p, isHost: s.isHost),
        ],
      ),
    );
  }

  static int _rank(Participant p) => switch (p.status) {
        'pending' => 0,
        'active' => p.isHost ? 1 : 2,
        'left' => 3,
        _ => 4,
      };
}

class _ParticipantTile extends StatelessWidget {
  final Participant p;
  final bool isHost;
  const _ParticipantTile({required this.p, required this.isHost});

  Future<void> _act(BuildContext context, String action) async {
    final s = context.read<SessionController>();
    if (action == 'remove' || action == 'block') {
      final ok = await confirmDialog(
        context,
        title: action == 'block' ? 'Block ${p.name}?' : 'Remove ${p.name}?',
        message: action == 'block'
            ? 'They will be disconnected and this device cannot rejoin this session. Their uploads stay in the gallery.'
            : 'They will be disconnected. They can rejoin with the PIN. Their uploads stay in the gallery.',
        confirm: action == 'block' ? 'Block' : 'Remove',
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      await s.participantAction(p.id, action);
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (p.status) {
      'pending' => 'Waiting for approval',
      'active' => p.online ? 'Online' : 'Offline',
      'left' => 'Left',
      'removed' => 'Removed',
      'blocked' => 'Blocked',
      _ => p.status,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Avatar(p.initials, color: avatarColor(p.avatarColor), online: p.isActive ? p.online : null),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.isHost ? '${p.name} (Host)' : p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            Text('$status · ${p.items} items · ${formatBytes(p.bytes)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
        if (isHost && p.isPending) ...[
          TextButton(onPressed: () => _act(context, 'reject'), child: const Text('Deny')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => _act(context, 'approve'),
              child: const Text('Allow')),
        ] else if (isHost && !p.isHost && p.isActive)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.muted),
            onSelected: (a) => _act(context, a),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'remove', child: Text('Remove')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
      ]),
    );
  }
}
