import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_controller.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'participants_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _timer;
  StreamSubscription<ServerEvent>? _sub;
  late final SessionController _s = context.read<SessionController>();

  @override
  void initState() {
    super.initState();
    _s.refreshStats();
    // Live while visible: periodic refresh + event-driven refresh.
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _s.refreshStats();
    });
    Timer? debounce;
    _sub = _s.events.listen((e) {
      if (e.type.startsWith('media_') || e.type.startsWith('upload_') || e.type.startsWith('participant_')) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 700), () {
          if (mounted) _s.refreshStats();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final st = s.stats;
    final storage = st?.storage;
    final used = storage?.sessionBytes ?? 0;
    final free = storage?.freeBytes;
    final total = storage?.totalBytes;
    return PageShell(
      title: 'Session dashboard',
      subtitle: 'A quick overview of your group’s activity.',
      onRefresh: s.refreshStats,
      child: st == null
          ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          : Column(children: [
              Row(children: [
                Expanded(child: _StatCard(icon: Icons.photo_outlined, value: '${st.photos}', label: 'Photos')),
                const SizedBox(width: 9),
                Expanded(child: _StatCard(icon: Icons.videocam_outlined, value: '${st.videos}', label: 'Videos')),
                const SizedBox(width: 9),
                Expanded(child: _StatCard(icon: Icons.storage_outlined, value: formatBytes(st.mediaBytes), label: 'Total')),
              ]),
              const SizedBox(height: 9),
              Row(children: [
                Expanded(child: _StatCard(icon: Icons.people_outline, value: '${st.onlineCount}', label: 'Online now')),
                const SizedBox(width: 9),
                Expanded(child: _StatCard(icon: Icons.cloud_upload_outlined, value: '${st.activeUploads.length}', label: 'Active uploads')),
                const SizedBox(width: 9),
                Expanded(child: _StatCard(icon: Icons.timer_outlined, value: formatDuration(st.durationMs), label: 'Running')),
              ]),
              const SizedBox(height: 22),
              SectionTitle('Participants', trailing: s.isHost ? 'Manage' : null, onTrailing: () => showParticipantsSheet(context)),
              const SizedBox(height: 12),
              for (final p in st.participants.where((p) => p.isActive))
                _MemberRow(p, '${formatBytes(p.bytes)} · ${p.items} item${p.items == 1 ? '' : 's'}${p.online ? '' : ' · offline'}'),
              if (st.activeUploads.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionTitle('Uploading now'),
                const SizedBox(height: 12),
                for (final u in st.activeUploads)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${u.participantName ?? 'Someone'} · ${u.filename}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                          value: u.size == 0 ? 0 : u.received / u.size,
                          minHeight: 6,
                          backgroundColor: AppColors.lavender,
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8)),
                    ]),
                  ),
              ],
              const SizedBox(height: 22),
              SectionTitle(s.isHost ? 'Storage on this device' : 'Storage on the host'),
              const SizedBox(height: 12),
              SurfaceCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Used by session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    Text(formatBytes(used), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (total == null || total == 0) ? 0 : ((total - (free ?? 0)) / total).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: AppColors.lavender,
                    color: (storage?.lowStorage ?? false) ? AppColors.red : AppColors.primary,
                  ),
                  const SizedBox(height: 9),
                  Text(free == null ? 'Free space unknown' : '${formatBytes(free)} free of ${formatBytes(total)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  if (storage?.lowStorage ?? false) ...[
                    const SizedBox(height: 10),
                    const InfoBanner('Storage is low. Large uploads will be refused until space is freed.', error: true),
                  ],
                ]),
              ),
              if (st.recentActivity.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionTitle('Recent activity'),
                const SizedBox(height: 8),
                for (final a in st.recentActivity.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Icon(_activityIcon(a.kind), size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(a.detail, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                      Text(formatTime(DateTime.fromMillisecondsSinceEpoch(a.ts)),
                          style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                    ]),
                  ),
              ],
            ]),
    );
  }

  IconData _activityIcon(String kind) => switch (kind) {
        'media_uploaded' => Icons.add_photo_alternate_outlined,
        'media_deleted' => Icons.delete_outline,
        'upload_failed' => Icons.error_outline,
        'participant_joined' || 'participant_reconnected' || 'participant_approved' => Icons.person_add_alt_1_outlined,
        'participant_left' || 'participant_removed' => Icons.person_remove_outlined,
        _ => Icons.bolt_outlined,
      };
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const _StatCard({required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(height: 8),
        FittedBox(child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      ]));
}

class _MemberRow extends StatelessWidget {
  final Participant p;
  final String detail;
  const _MemberRow(this.p, this.detail);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Avatar(p.initials, color: avatarColor(p.avatarColor), online: p.online),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.isHost ? '${p.name} (Host)' : p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ])),
      ]));
}
