import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/app/app.dart';
import 'package:localdrop/providers/session_controller.dart';
import 'package:localdrop/screens/session_shell.dart';
import 'package:localdrop/services/ads.dart';
import 'package:localdrop/widgets/ad_banner.dart';

import '../support.dart';
import 'screens_test.dart' as w;

class RecordingAds extends NoAdService {
  int interstitials = 0;
  @override
  Future<void> showInterstitialAtBreak() async => interstitials++;
}

void main() {
  testWidgets('without an ad SDK (offline / tests) banners take no space', (t) async {
    final s = w.services();
    await w.pumpApp(t, s);
    expect(find.byType(AdBanner), findsOneWidget);
    expect(t.getSize(find.byType(AdBanner)).height, 0);
    expect(find.text('Create Session'), findsOneWidget);
  });

  testWidgets('full-screen ad is shown only at the session-end break', (t) async {
    final ads = RecordingAds();
    final s = AppServices.create(
      engine: FakeEngine(),
      prefs: memoryPreferences(),
      saver: FolderSaver(Directory.systemTemp),
      dataDir: () async => Directory.systemTemp.path,
      workDir: () async => Directory.systemTemp,
      ads: ads,
    );
    w.activeSession(s);
    s.session.phase = SessionPhase.ended;
    s.session.endedMessage = 'The host ended this session.';
    await w.pumpApp(t, s, home: const SessionShell());
    expect(ads.interstitials, 0);
    await t.tap(find.text('Back to home'));
    await t.pumpAndSettle();
    expect(ads.interstitials, 1);
    expect(find.text('Create Session'), findsOneWidget);
  });
}
