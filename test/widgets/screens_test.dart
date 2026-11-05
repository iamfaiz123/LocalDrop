import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/app/app.dart';
import 'package:localdrop/models/models.dart';
import 'package:localdrop/providers/session_controller.dart';
import 'package:localdrop/screens/create_session_screen.dart';
import 'package:localdrop/screens/join_details_screen.dart';
import 'package:localdrop/screens/join_session_screen.dart';
import 'package:localdrop/screens/media_viewer_screen.dart';
import 'package:localdrop/screens/session_shell.dart';
import 'package:localdrop/screens/starting_screen.dart';
import 'package:localdrop/services/api_client.dart';
import 'package:localdrop/services/download_manager.dart';
import 'package:localdrop/services/realtime_service.dart';
import 'package:localdrop/services/upload_manager.dart';
import 'package:localdrop/widgets/ui.dart';

import '../support.dart';

late FakeEngine engine;
final _now = DateTime.now();
final _today1024 = DateTime(_now.year, _now.month, _now.day, 10, 24);

AppServices services() {
  engine = FakeEngine();
  return AppServices.create(
    engine: engine,
    prefs: memoryPreferences(),
    saver: FolderSaver(Directory.systemTemp),
    dataDir: () async => Directory.systemTemp.path,
    workDir: () async => Directory.systemTemp,
  );
}

Future<void> pumpApp(WidgetTester t, AppServices s, {Widget? home}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(LocalDropApp(services: s, restoreOnStart: false, home: home));
  await t.pump();
}

MediaItem item(int i, {bool video = false, String uploader = 'p1', String name = 'Riya'}) => MediaItem(
      id: i.toRadixString(16).padLeft(32, '0'),
      filename: video ? 'VID_$i.MP4' : 'IMG_$i.JPG',
      mime: video ? 'video/mp4' : 'image/jpeg',
      kind: video ? 'video' : 'photo',
      ext: video ? 'mp4' : 'jpg',
      size: 1000 * i,
      sha256: 'c' * 64,
      createdAt: _today1024.millisecondsSinceEpoch,
      hasThumbnail: true,
      uploader: Uploader(id: uploader, name: name, initials: name[0]),
    );

/// Puts the controllers into an active session without any network.
void activeSession(AppServices s, {bool host = false}) {
  final c = s.session;
  c.role = host ? SessionRole.host : SessionRole.participant;
  c.phase = SessionPhase.active;
  c.connection = ConnectionStatus.connected;
  c.me = Participant(id: host ? 'h' : 'p1', name: host ? 'Aarav' : 'Riya', role: host ? 'host' : 'participant');
  c.session = SessionInfo(
    id: 'a' * 32,
    name: 'Manali Trip 2026',
    hostName: 'Aarav',
    uploadPermission: 'everyone',
    downloadPermission: 'everyone',
    pin: host ? '837201' : null,
  );
  c.participants = const [
    Participant(id: 'h', name: 'Aarav', role: 'host', initials: 'A', online: true, photos: 2),
    Participant(id: 'p1', name: 'Riya', initials: 'R', online: true, photos: 1, videos: 1),
  ];
}

void main() {
  testWidgets('landing → create session validates and shows network status', (t) async {
    final s = services();
    await pumpApp(t, s);
    expect(find.text('Original quality'), findsOneWidget);
    expect(find.text('Works offline'), findsOneWidget);
    await t.tap(find.text('Create Session'));
    await t.pumpAndSettle();
    expect(find.byType(CreateSessionScreen), findsOneWidget);
    expect(find.textContaining('Wi-Fi ready · 192.168.1.20'), findsOneWidget);

    await t.scrollUntilVisible(find.widgetWithText(FilledButton, 'Create Session'), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.widgetWithText(FilledButton, 'Create Session'));
    await t.pump();
    expect(find.text('Enter a session name'), findsOneWidget);
    expect(find.text('Enter your name'), findsNWidgets(2)); // hint + validation error
  });

  testWidgets('create session warns when there is no network', (t) async {
    final s = services();
    engine.ifaces = const [];
    await pumpApp(t, s, home: const CreateSessionScreen());
    await t.pumpAndSettle();
    expect(find.textContaining('No hotspot or Wi-Fi network detected'), findsOneWidget);
  });

  testWidgets('starting screen reports a server start failure', (t) async {
    final s = services();
    engine.startError = Exception('Address already in use');
    await pumpApp(t, s, home: const StartingScreen());
    await t.runAsync(() => s.session.createSession(sessionName: 'Trip', hostName: 'Aarav'));
    await t.pumpAndSettle();
    expect(find.text('Couldn’t start your session'), findsOneWidget);
    expect(find.textContaining('Address already in use'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
  });

  testWidgets('join screen rejects an invalid address', (t) async {
    final s = services();
    await pumpApp(t, s, home: const JoinSessionScreen(enableCamera: false));
    expect(find.text('Connect'), findsOneWidget);
    await t.enterText(find.byKey(const Key('address')), 'not a url');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.textContaining('Enter an address like'), findsOneWidget);
  });

  testWidgets('join details validates the PIN', (t) async {
    final s = services();
    await pumpApp(t, s,
        home: JoinDetailsScreen(
          base: Uri.parse('http://192.168.1.20:8080'),
          info: const SessionInfo(id: 'x', name: 'Manali Trip 2026', hostName: 'Aarav', pinLength: 6),
        ));
    expect(find.text('Manali Trip 2026'), findsOneWidget);
    await t.enterText(find.byKey(const Key('joinName')), 'Riya');
    await t.enterText(find.byKey(const Key('joinPin')), '12');
    await t.tap(find.text('Join Session'));
    await t.pump();
    expect(find.text('Enter the PIN shown on the host’s screen'), findsOneWidget);
  });

  testWidgets('gallery renders items, counts and video badges', (t) async {
    final s = services();
    activeSession(s);
    final api = ApiClient(Uri.parse('http://127.0.0.1:9'), token: 'f' * 64);
    s.gallery.debugShow(api, [item(1), item(2, video: true), item(3)], meId: 'p1');
    await pumpApp(t, s, home: const SessionShell());
    await t.pump();
    expect(find.text('Manali Trip 2026'), findsOneWidget);
    expect(find.text('2 members · 3 items'), findsOneWidget);
    expect(find.byType(MediaTile), findsNWidgets(3));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Add to pool'), findsOneWidget);
    expect(find.text('CONNECTED'), findsOneWidget);
  });

  testWidgets('gallery empty, error and uploads-disabled states', (t) async {
    final s = services();
    activeSession(s);
    final api = ApiClient(Uri.parse('http://127.0.0.1:9'));
    s.gallery.debugShow(api, const [], meId: 'p1');
    await pumpApp(t, s, home: const SessionShell());
    expect(find.text('No photos or videos yet'), findsOneWidget);

    s.gallery.debugShow(api, const [], meId: 'p1', error: 'Cannot reach the host');
    s.session.session = const SessionInfo(id: 'x', name: 'Trip', hostName: 'A', uploadPermission: 'host_only');
    s.session.connection = ConnectionStatus.reconnecting;
    s.session.notifyListeners();
    await t.pump();
    expect(find.text('Couldn’t load the gallery'), findsOneWidget);
    expect(find.text('Cannot reach the host'), findsOneWidget);
    expect(find.text('Uploads are turned off'), findsOneWidget);
    expect(find.textContaining('Reconnecting'), findsWidgets);
  });

  testWidgets('tab navigation and host controls', (t) async {
    final s = services();
    activeSession(s, host: true);
    s.session.stats = const SessionStats(photos: 248, videos: 32, mediaBytes: 13314398618, participants: [
      Participant(id: 'h', name: 'Aarav', role: 'host', initials: 'A', online: true, photos: 86),
    ]);
    s.gallery.debugShow(ApiClient(Uri.parse('http://127.0.0.1:9')), const [], meId: 'h', isHost: true);
    await pumpApp(t, s, home: const SessionShell());

    await t.tap(find.byKey(const Key('tab-2')));
    await t.pump();
    expect(find.text('Session dashboard'), findsOneWidget);
    expect(find.text('248'), findsOneWidget);
    expect(find.text('12.4 GB'), findsOneWidget);

    await t.tap(find.byKey(const Key('tab-3')));
    await t.pump();
    expect(find.text('Session settings'), findsOneWidget);
    expect(find.text('Everyone can upload'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('endSession')), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('endSession')));
    await t.pumpAndSettle();
    expect(find.text('End session for everyone?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(s.session.phase, SessionPhase.active);

    await t.tap(find.byKey(const Key('tab-1')));
    await t.pump();
    expect(find.text('Manage your transfers.'), findsOneWidget);
  });

  testWidgets('upload and download states', (t) async {
    final s = services();
    activeSession(s);
    s.gallery.debugShow(ApiClient(Uri.parse('http://127.0.0.1:9')), const [], meId: 'p1');
    UploadTask task(String name, TransferState st, {int sent = 0, String? error}) =>
        UploadTask(id: name, path: '/nonexistent/$name', name: name, size: 1000, isVideo: name.endsWith('MP4'))
          ..state = st
          ..sent = sent
          ..speed = 12.4 * 1024 * 1024
          ..error = error;
    s.uploads.tasks.addAll([
      task('IMG_4829.JPG', TransferState.uploading, sent: 720),
      task('VID_0193.MP4', TransferState.paused, sent: 340),
      task('IMG_4830.JPG', TransferState.queued),
      task('IMG_4831.JPG', TransferState.failed, error: 'The host is out of storage space'),
      task('IMG_4800.JPG', TransferState.done, sent: 1000),
    ]);
    s.downloads.tasks.add(DownloadTask.media(item(5))
      ..state = TransferState.done
      ..savedTo = 'Gallery › LocalDrop');
    await pumpApp(t, s, home: const SessionShell());
    await t.tap(find.byKey(const Key('tab-1')));
    await t.pump();

    expect(find.text('Uploading (4)'), findsOneWidget);
    expect(find.text('72%'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.textContaining('12.4 MB/s'), findsOneWidget);
    expect(find.textContaining('out of storage space'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
    expect(find.byTooltip('Resume'), findsOneWidget);

    await t.tap(find.text('Completed'));
    await t.pump();
    expect(find.text('IMG_4800.JPG'), findsOneWidget);
    expect(find.textContaining('Done'), findsOneWidget);

    await t.ensureVisible(find.text('Downloads (0)'));
    await t.tap(find.text('Downloads (0)'));
    await t.pump();
    expect(find.text('IMG_5.JPG'), findsOneWidget);
    expect(find.text('Saved to Gallery › LocalDrop'), findsOneWidget);
  });

  testWidgets('media viewer shows uploader, position and actions', (t) async {
    final s = services();
    activeSession(s);
    s.gallery.debugShow(ApiClient(Uri.parse('http://127.0.0.1:9')), [item(1), item(2, uploader: 'p2', name: 'Karan')], meId: 'p1');
    await pumpApp(t, s, home: const MediaViewerScreen(initialIndex: 1));
    await t.pump();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Karan'), findsOneWidget);
    expect(find.textContaining('Today, 10:24 AM'), findsOneWidget);
    expect(find.byTooltip('Save original to gallery'), findsOneWidget);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);
  });

  testWidgets('ended session returns home', (t) async {
    final s = services();
    activeSession(s);
    s.session.phase = SessionPhase.ended;
    s.session.endedMessage = 'The host ended this session.';
    await pumpApp(t, s, home: const SessionShell());
    expect(find.text('Session ended'), findsOneWidget);
    expect(find.text('The host ended this session.'), findsOneWidget);
    await t.tap(find.text('Back to home'));
    await t.pumpAndSettle();
    expect(find.text('Create Session'), findsOneWidget);
    expect(s.session.phase, SessionPhase.idle);
  });

  testWidgets('home hides create/join while the device belongs to a session', (t) async {
    final s = services();
    s.session.locked = const LockedSession(SessionRole.host, 'Manali Trip 2026', 'Your session could not be restarted');
    await pumpApp(t, s);
    expect(find.byKey(const Key('activeSession')), findsOneWidget);
    expect(find.text('You are hosting “Manali Trip 2026”'), findsOneWidget);
    expect(find.text('Create Session'), findsNothing);
    expect(find.text('Join Session'), findsNothing);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
  });
}
