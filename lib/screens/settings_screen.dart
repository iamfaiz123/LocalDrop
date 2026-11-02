import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/gallery_controller.dart';
import '../providers/session_controller.dart';
import '../services/api_client.dart';
import '../services/upload_manager.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'host_lobby_screen.dart';
import 'landing_screen.dart';
import 'participants_sheet.dart';
import 'selection_screen.dart';

/// Host controls (host) or session info + leave (participant).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    return s.isHost ? const _HostControls() : const _ParticipantSession();
  }
}

class _HostControls extends StatelessWidget {
  const _HostControls();

  Future<void> _update(BuildContext context, Map<String, Object> changes) async {
    try {
      await context.read<SessionController>().updateSettings(changes);
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message, error: true);
    }
  }

  Future<void> _rename(BuildContext context, String current) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Session name', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(controller: c, autofocus: true, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != current && context.mounted) await _update(context, {'name': name});
  }

  Future<void> _permission(BuildContext context, String key, String title, String current) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (b) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(18), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          RadioGroup<String>(
            groupValue: current,
            onChanged: (x) => Navigator.pop(b, x),
            child: const Column(children: [
              RadioListTile(value: 'everyone', title: Text('Everyone')),
              RadioListTile(value: 'host_only', title: Text('Only me (host)')),
            ]),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (v != null && v != current && context.mounted) await _update(context, {key: v});
  }

  Future<void> _end(BuildContext context) async {
    final s = context.read<SessionController>();
    var deleteMedia = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('End session for everyone?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Everyone is disconnected and unfinished uploads are discarded.',
                style: TextStyle(color: AppColors.muted, height: 1.45)),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: deleteMedia,
              onChanged: (v) => set(() => deleteMedia = v ?? false),
              title: const Text('Also delete all shared media from this phone', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Save anything you want to keep first.', style: TextStyle(fontSize: 11)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('End Session', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await s.endSession(deleteMedia: deleteMedia);
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final info = s.session!;
    return PageShell(
      title: 'Session settings',
      subtitle: 'Manage access and session preferences.',
      child: Column(children: [
        SurfaceCard(
          child: Column(children: [
            _SettingRow(Icons.edit_outlined, 'Session name', info.name, onTap: () => _rename(context, info.name)),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.cloud_upload_outlined, 'Upload permission',
                info.uploadsOpen ? 'Everyone can upload' : 'Only you can upload',
                onTap: () => _permission(context, 'upload_permission', 'Who can upload?', info.uploadPermission ?? 'everyone')),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.download_outlined, 'Download permission',
                info.downloadsOpen ? 'Everyone can download' : 'Only you can download',
                onTap: () => _permission(context, 'download_permission', 'Who can download?', info.downloadPermission ?? 'everyone')),
            const Divider(color: AppColors.border),
            _SwitchRow(Icons.how_to_reg_outlined, 'Approve new members', 'Ask before someone joins', info.requireApproval,
                (v) => _update(context, {'require_approval': v})),
            const Divider(color: AppColors.border),
            _SwitchRow(Icons.save_outlined, 'Keep media after ending', 'Files stay on this phone', info.keepMedia,
                (v) => _update(context, {'keep_media': v})),
          ]),
        ),
        const SizedBox(height: 15),
        SurfaceCard(
          child: Column(children: [
            _SettingRow(Icons.qr_code_2, 'Invite people', 'Show QR code, PIN and address',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HostLobbyScreen()))),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.groups_outlined, 'Manage participants', 'View, remove or block members',
                onTap: () => showParticipantsSheet(context)),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.delete_outline, 'Delete media', 'Remove photos and videos', onTap: () {
              context.read<GalleryController>().startSelection();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectionScreen()));
            }),
          ]),
        ),
        const SizedBox(height: 22),
        GestureDetector(
          key: const Key('endSession'),
          onTap: () => _end(context),
          child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFFFD2D5))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.power_settings_new, color: AppColors.red),
                SizedBox(width: 9),
                Text('End Session', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900)),
              ])),
        ),
        const SizedBox(height: 16),
        const Text(
          'Security: only people with the PIN can join. Transfers use plain HTTP on your local network and are not encrypted.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4),
        ),
      ]),
    );
  }
}

class _ParticipantSession extends StatelessWidget {
  const _ParticipantSession();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final info = s.session!;
    return PageShell(
      title: 'Session',
      subtitle: 'Hosted by ${info.hostName}',
      child: Column(children: [
        SurfaceCard(
          child: Column(children: [
            _SettingRow(Icons.landscape_outlined, 'Session name', info.name),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.cloud_upload_outlined, 'Uploads', info.uploadsOpen ? 'Everyone can upload' : 'Only the host can upload'),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.download_outlined, 'Downloads', info.downloadsOpen ? 'Everyone can download' : 'Only the host can download'),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.groups_outlined, 'Participants', '${s.activeMembers} members', onTap: () => showParticipantsSheet(context)),
            const Divider(color: AppColors.border),
            _SettingRow(Icons.link, 'Connected to', s.api?.baseUri.toString() ?? ''),
          ]),
        ),
        const SizedBox(height: 22),
        GestureDetector(
          key: const Key('leaveSession'),
          onTap: () async {
            final busy = s.uploads.active.any((t) => t.state == TransferState.uploading);
            final ok = await confirmDialog(context,
                title: 'Leave session?',
                message: busy ? 'Uploads in progress will stop.' : 'You can rejoin later with the PIN.',
                confirm: 'Leave',
                destructive: true);
            if (!ok || !context.mounted) return;
            await s.leave();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LandingScreen()), (_) => false);
            }
          },
          child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFFFD2D5))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.logout, color: AppColors.red),
                SizedBox(width: 9),
                Text('Leave Session', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900)),
              ])),
        ),
      ]),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final VoidCallback? onTap;
  const _SettingRow(this.icon, this.title, this.detail, {this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              ])),
              if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.muted),
            ])),
      );
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(this.icon, this.title, this.detail, this.value, this.onChanged);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ])),
        Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: AppColors.primary),
      ]));
}
