import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ledger/identity.dart';
import '../ledger/ledger_store.dart';
import '../platform/incoming_imports.dart';
import '../platform/native_bridge.dart';
import '../providers/ledger_controller.dart';
import '../providers/gallery_controller.dart';
import '../providers/pool_controller.dart';
import '../providers/session_controller.dart';
import '../screens/landing_screen.dart';
import '../screens/session_shell.dart';
import '../screens/trips_screen.dart';
import '../services/ads.dart';
import '../services/download_manager.dart';
import '../services/device_library.dart';
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
  final AdService ads;
  final PoolController pool;
  final LedgerController ledger;
  final IncomingImports incoming;

  AppServices._(this.prefs, this.session, this.gallery, this.uploads, this.downloads, this.ads, this.pool, this.ledger, this.incoming);

  factory AppServices.create({
    required EngineService engine,
    required Preferences prefs,
    required MediaSaver saver,
    required Future<String> Function() dataDir,
    required Future<Directory> Function() workDir,
    String? tempDir,
    NativeBridge native = const NativeBridge(),
    AdService? ads,
    DeviceLibrary? library,
    UploadManager? uploads,
    LedgerController? ledger,
  }) {
    final gallery = GalleryController();
    uploads ??= UploadManager(
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
    final pool = PoolController(library: library ?? PhotoManagerLibrary(), prefs: prefs, uploads: uploads);
    return AppServices._(prefs, session, gallery, uploads, downloads, ads ?? NoAdService(), pool,
        ledger ?? LedgerController(store: MemoryLedgerStore(), keys: MemoryKeyStore()), IncomingImports());
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
      ads: createAdService(),
      ledger: LedgerController(
        store: FileLedgerStore(() async => support),
        keys: SecureKeyStore(),
        shareSink: (fileName, content, message) async {
          final dir = Directory('${tmp.path}/share');
          await dir.create(recursive: true);
          final f = File('${dir.path}/$fileName');
          await f.writeAsString(content, flush: true);
          await SharePlus.instance.share(ShareParams(
            text: message,
            files: [XFile(f.path, name: fileName, mimeType: 'application/octet-stream')],
          ));
        },
      ),
    );
  }
}

class LocalDropApp extends StatefulWidget {
  final AppServices services;
  final bool restoreOnStart;

  /// Overrides the first screen (tests).
  final Widget? home;
  const LocalDropApp({super.key, required this.services, this.restoreOnStart = true, this.home});

  @override
  State<LocalDropApp> createState() => _LocalDropAppState();
}

class _LocalDropAppState extends State<LocalDropApp> {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _incoming;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    // Trip expense files opened from WhatsApp land here.
    _incoming = services.incoming.stream.listen((text) async {
      await services.ledger.init();
      final ctx = _navigator.currentContext;
      if (ctx != null && ctx.mounted) await openImported(ctx, services.ledger, text);
    });
    services.incoming.start();
  }

  @override
  void dispose() {
    _incoming?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          Provider.value(value: services.prefs),
          ChangeNotifierProvider.value(value: services.session),
          ChangeNotifierProvider.value(value: services.gallery),
          ChangeNotifierProvider.value(value: services.uploads),
          ChangeNotifierProvider.value(value: services.downloads),
          ChangeNotifierProvider<AdService>.value(value: services.ads),
          ChangeNotifierProvider.value(value: services.pool),
          ChangeNotifierProvider.value(value: services.ledger),
        ],
        child: MaterialApp(
          navigatorKey: _navigator,
          title: 'LocalDrop',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: widget.home ?? (widget.restoreOnStart ? const _RestoreGate() : const LandingScreen()),
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
