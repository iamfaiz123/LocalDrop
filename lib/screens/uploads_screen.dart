import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_controller.dart';
import '../services/download_manager.dart';
import '../services/upload_manager.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'gallery_screen.dart';

enum _Tab { uploading, completed, downloads }

class UploadsScreen extends StatefulWidget {
  const UploadsScreen({super.key});
  @override
  State<UploadsScreen> createState() => _UploadsScreenState();
}

class _UploadsScreenState extends State<UploadsScreen> {
  _Tab _tab = _Tab.uploading;

  @override
  Widget build(BuildContext context) {
    final up = context.watch<UploadManager>();
    final down = context.watch<DownloadManager>();
    final s = context.watch<SessionController>();
    final canUpload = s.isHost || (s.session?.uploadsOpen ?? true);
    final rows = switch (_tab) {
      _Tab.uploading => up.active.map<Widget>((t) => _UploadRow(task: t, manager: up)).toList(),
      _Tab.completed => up.completed.reversed.map<Widget>((t) => _UploadRow(task: t, manager: up)).toList(),
      _Tab.downloads => down.tasks.reversed.map<Widget>((t) => _DownloadRow(task: t, manager: down)).toList(),
    };
    return PageShell(
      title: 'Uploads',
      subtitle: 'Manage your transfers.',
      child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Pill('Uploading (${up.active.length})', selected: _tab == _Tab.uploading, onTap: () => setState(() => _tab = _Tab.uploading)),
            const SizedBox(width: 8),
            Pill('Completed', selected: _tab == _Tab.completed, onTap: () => setState(() => _tab = _Tab.completed)),
            const SizedBox(width: 8),
            Pill('Downloads (${down.active.length})',
                selected: _tab == _Tab.downloads, onTap: () => setState(() => _tab = _Tab.downloads)),
          ]),
        ),
        const SizedBox(height: 20),
        if (rows.isEmpty)
          StateMessage(
            icon: _tab == _Tab.downloads ? Icons.download_outlined : Icons.cloud_upload_outlined,
            title: switch (_tab) {
              _Tab.uploading => 'Nothing uploading',
              _Tab.completed => 'No finished uploads yet',
              _Tab.downloads => 'No downloads yet',
            },
            detail: _tab == _Tab.downloads
                ? 'Select photos in the gallery and tap Download to save originals.'
                : 'Files you share appear here with their progress.',
          )
        else
          ...rows,
        if (_tab == _Tab.completed && up.completed.isNotEmpty)
          TextButton(onPressed: up.clearFinished, child: const Text('Clear finished')),
        if (_tab == _Tab.downloads && down.completed.isNotEmpty)
          TextButton(onPressed: down.clearFinished, child: const Text('Clear finished')),
        const SizedBox(height: 20),
        if (_tab != _Tab.downloads)
          OutlineAction(
            label: canUpload ? 'Add more files' : 'Uploads are turned off by the host',
            icon: Icons.add,
            onPressed: canUpload ? () => pickAndUpload(context) : null,
          ),
      ]),
    );
  }
}

String _stateText(TransferState s) => switch (s) {
      TransferState.queued => 'Waiting…',
      TransferState.preparing => 'Preparing…',
      TransferState.uploading => '',
      TransferState.paused => 'Paused',
      TransferState.verifying => 'Verifying integrity…',
      TransferState.done => 'Done',
      TransferState.duplicate => 'Already in the gallery',
      TransferState.failed => 'Failed',
      TransferState.cancelled => 'Cancelled',
    };

class _TransferRow extends StatelessWidget {
  final Widget thumb;
  final String name;
  final String detail;
  final double progress;
  final String percent;
  final TransferState state;
  final List<Widget> actions;
  const _TransferRow({
    required this.thumb,
    required this.name,
    required this.detail,
    required this.progress,
    required this.percent,
    required this.state,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(children: [
          SizedBox(width: 65, height: 65, child: ClipRRect(borderRadius: BorderRadius.circular(13), child: thumb)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: state == TransferState.failed ? AppColors.red : AppColors.muted, fontSize: 10)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state == TransferState.preparing || state == TransferState.verifying ? null : progress,
                  minHeight: 6,
                  backgroundColor: AppColors.lavender,
                  color: state == TransferState.failed
                      ? AppColors.red
                      : state.isFinished
                          ? AppColors.green
                          : AppColors.primary,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 9),
          Text(percent, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10)),
          ...actions,
        ]),
      );
}

Widget _iconAction(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: AppColors.primary),
      onPressed: onTap,
    );

class _UploadRow extends StatelessWidget {
  final UploadTask task;
  final UploadManager manager;
  const _UploadRow({required this.task, required this.manager});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final placeholder = Container(
        color: const Color(0xFFDCD6F5), child: Icon(t.isVideo ? Icons.movie_outlined : Icons.photo_outlined, color: AppColors.primary));
    final thumb = t.isVideo
        ? placeholder
        : Image.file(File(t.path), fit: BoxFit.cover, cacheWidth: 130, errorBuilder: (_, __, ___) => placeholder);
    final detail = switch (t.state) {
      TransferState.uploading => '${formatBytes(t.size)} · ${formatSpeed(t.speed)}',
      _ => '${formatBytes(t.size)} · ${t.error ?? _stateText(t.state)}',
    };
    final pct = switch (t.state) {
      TransferState.queued => 'Queued',
      TransferState.uploading || TransferState.paused => '${(t.progress * 100).floor()}%',
      _ => '',
    };
    return _TransferRow(
      thumb: thumb,
      name: t.name,
      detail: detail,
      progress: t.progress,
      percent: pct,
      state: t.state,
      actions: [
        if (t.state == TransferState.uploading || t.state == TransferState.queued || t.state == TransferState.preparing)
          _iconAction(Icons.pause_rounded, 'Pause', () => manager.pause(t)),
        if (t.state == TransferState.paused) _iconAction(Icons.play_arrow_rounded, 'Resume', () => manager.resume(t)),
        if (t.state == TransferState.failed) _iconAction(Icons.refresh, 'Retry', () => manager.resume(t)),
        if (t.state.isActive && t.state != TransferState.verifying) _iconAction(Icons.close, 'Cancel', () => manager.cancel(t)),
      ],
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadTask task;
  final DownloadManager manager;
  const _DownloadRow({required this.task, required this.manager});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final thumb = Container(
      color: const Color(0xFFDCD6F5),
      child: Icon(t.isZip ? Icons.folder_zip_outlined : (t.media!.isVideo ? Icons.movie_outlined : Icons.photo_outlined),
          color: AppColors.primary),
    );
    final detail = switch (t.state) {
      TransferState.uploading => '${formatBytes(t.total)} · ${formatSpeed(t.speed)}',
      TransferState.done => 'Saved to ${t.savedTo ?? 'device'}',
      _ => '${formatBytes(t.total)} · ${t.error ?? _stateText(t.state)}',
    };
    return _TransferRow(
      thumb: thumb,
      name: t.title,
      detail: detail,
      progress: t.progress,
      percent: t.state == TransferState.uploading || t.state == TransferState.paused ? '${(t.progress * 100).floor()}%' : '',
      state: t.state,
      actions: [
        if (t.state == TransferState.uploading || t.state == TransferState.queued) _iconAction(Icons.pause_rounded, 'Pause', () => manager.pause(t)),
        if (t.state == TransferState.paused) _iconAction(Icons.play_arrow_rounded, 'Resume', () => manager.resume(t)),
        if (t.state == TransferState.failed) _iconAction(Icons.refresh, 'Retry', () => manager.resume(t)),
        if (t.state.isActive && t.state != TransferState.verifying) _iconAction(Icons.close, 'Cancel', () => manager.cancel(t)),
      ],
    );
  }
}
