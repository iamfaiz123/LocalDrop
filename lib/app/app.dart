import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../platform/native_bridge.dart';
import '../providers/gallery_controller.dart';
import '../providers/session_controller.dart';
import '../screens/landing_screen.dart';
import '../screens/session_shell.dart';
import '../services/download_manager.dart';
import '../services/engine_service.dart';
import '../services/media_saver.dart';
import '../services/preferences.dart';
import '../services/upload_manager.dart';
import '../theme.dart';

/// Everything the UI depends on. Tests construct it with fakes.
class AppServices {
  final Preferences prefs;
  final SessionController session;
  final GalleryController gallery;
  final UploadManager uploads;
  final DownloadManager downloads;

  AppServices._(this.prefs, this.session, this.gallery, this.uploads, this.downloads);

  factory AppServices.create({
    required EngineService engine,
    required Preferences prefs,
    required MediaSaver saver,
    required Future<String> Function() dataDir,
    required Future<Directory> Function() workDir,
    String? tempDir,
    NativeBridge native = const NativeBridge(),
  }) {
    final gallery = GalleryController();
    final uploads = UploadManager(
      native: native,
      tempDir: tempDir,
      store: JsonUploadStore(write: prefs.setRaw, read: prefs.getRaw),
    );
    final downloads = DownloadManager(saver: saver, workDir: workDir);
    final session = SessionController(
      engine: engine,
      prefs: prefs,
      dataDir: dataDir,
      gallery: gallery,
      uploads: uploads,
      downloads: downloads,
      native: native,
    );
    return AppServices._(prefs, session, gallery, uploads, downloads);
  }

  /// Production wiring.
  static Future<AppServices> production() async {
    final support = await getApplicationSupportDirectory();
    final tmp = await getTemporaryDirectory();
    return AppServices.create(
      engine: FfiEngineService(),
      prefs: Preferences(),
      saver: GalMediaSaver(),
      dataDir: () async => '${support.path}/localdrop',
      workDir: () async => tmp,
      tempDir: tmp.path,
    );
  }
}

class LocalDropApp extends StatelessWidget {
  final AppServices services;
  final bool restoreOnStart;

  /// Overrides the first screen (tests).
  final Widget? home;
  const LocalDropApp({super.key, required this.services, this.restoreOnStart = true, this.home});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          Provider.value(value: services.prefs),
          ChangeNotifierProvider.value(value: services.session),
          ChangeNotifierProvider.value(value: services.gallery),
          ChangeNotifierProvider.value(value: services.uploads),
          ChangeNotifierProvider.value(value: services.downloads),
        ],
        child: MaterialApp(
          title: 'LocalDrop',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: home ?? (restoreOnStart ? const _RestoreGate() : const LandingScreen()),
        ),
      );
}

/// Reconnects to a session that was active when the app was last closed.
class _RestoreGate extends StatefulWidget {
  const _RestoreGate();
  @override
  State<_RestoreGate> createState() => _RestoreGateState();
}

class _RestoreGateState extends State<_RestoreGate> {
  late final Future<bool> _restore = context.read<SessionController>().restore();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _restore,
        builder: (context, snap) {
          if (!snap.hasData && !snap.hasError) {
            return const Scaffold(
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cloud_outlined, color: AppColors.primary, size: 48),
                  SizedBox(height: 16),
                  CircularProgressIndicator(),
                ]),
              ),
            );
          }
          return snap.data == true ? const SessionShell() : const LandingScreen();
        },
      );
}
