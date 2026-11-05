import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/app/app.dart';
import 'package:localdrop/screens/pool_screen.dart';
import 'package:localdrop/services/device_library.dart';

import '../support.dart';
import 'screens_test.dart' as w;

Future<(AppServices, RecordingUploads, FakeDeviceLibrary)> setUpPool(WidgetTester t, {LibraryAccess access = LibraryAccess.full}) async {
  final uploads = RecordingUploads();
  final lib = FakeDeviceLibrary(20, accessResult: access);
  // Route the pool's uploads to the recorder.
  final services = AppServices.create(
    engine: FakeEngine(),
    prefs: memoryPreferences(),
    saver: FolderSaver(Directory.systemTemp),
    dataDir: () async => Directory.systemTemp.path,
    workDir: () async => Directory.systemTemp,
    library: lib,
    uploads: uploads,
  );
  w.activeSession(services);
  await w.pumpApp(t, services, home: const PoolScreen());
  await t.pumpAndSettle();
  return (services, uploads, lib);
}

void main() {
  testWidgets('swiping right shares, left skips', (t) async {
    final (s, uploads, _) = await setUpPool(t);
    expect(find.text('Drop to pool'), findsOneWidget);
    expect(find.text('20 left to review'), findsOneWidget);

    await t.drag(find.byType(SwipeCard), const Offset(320, 0));
    await t.pumpAndSettle();
    expect(uploads.queued, ['asset-0.jpg']);
    expect(find.text('1 shared'), findsOneWidget);

    await t.drag(find.byType(SwipeCard), const Offset(-320, 0));
    await t.pumpAndSettle();
    expect(uploads.queued, hasLength(1));
    expect(s.pool.skipped, {'asset-1'});

    // A short drag snaps back without deciding.
    await t.drag(find.byType(SwipeCard), const Offset(40, 0));
    await t.pumpAndSettle();
    expect(s.pool.current!.id, 'asset-2');
    expect(find.text('18 left to review'), findsOneWidget);
    await t.pump(const Duration(seconds: 1)); // flush debounced save
  });

  testWidgets('buttons share, skip and undo', (t) async {
    final (s, uploads, _) = await setUpPool(t);
    await t.tap(find.byKey(const Key('share')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('skip')));
    await t.pumpAndSettle();
    expect(uploads.queued, ['asset-0.jpg']);
    await t.tap(find.byKey(const Key('undo')));
    await t.pumpAndSettle();
    expect(s.pool.current!.id, 'asset-1');
    await t.pump(const Duration(seconds: 1)); // flush debounced save
  });

  testWidgets('select mode sends chosen items and marks them in pool', (t) async {
    final (_, uploads, _) = await setUpPool(t);
    await t.tap(find.text('Select'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('grid-asset-0')));
    await t.tap(find.byKey(const ValueKey('grid-asset-1')));
    await t.pump();
    expect(find.text('Send 2 to pool'), findsOneWidget);
    await t.tap(find.text('Send 2 to pool'));
    await t.pumpAndSettle();
    expect(uploads.queued, ['asset-0.jpg', 'asset-1.jpg']);
    expect(find.text('In pool'), findsNWidgets(2));
    await t.pump(const Duration(seconds: 1)); // flush debounced save
  });

  testWidgets('without photo access explains and offers settings', (t) async {
    await setUpPool(t, access: LibraryAccess.denied);
    expect(find.text('Allow access to your photos'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Choose files instead'), findsOneWidget);
    await t.pump(const Duration(seconds: 1)); // flush debounced save
  });
}
