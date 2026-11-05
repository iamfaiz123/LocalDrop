import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/app/app.dart';
import 'package:localdrop/ledger/identity.dart';
import 'package:localdrop/ledger/ledger_store.dart';
import 'package:localdrop/ledger/money.dart';
import 'package:localdrop/providers/ledger_controller.dart';
import 'package:localdrop/screens/trip_screen.dart';
import 'package:localdrop/screens/trips_screen.dart';

import '../support.dart';
import 'screens_test.dart' as w;

LedgerController phone(int seed, {List<String>? shared}) => LedgerController(
      store: MemoryLedgerStore(),
      keys: MemoryKeyStore(base64.encode(List.filled(32, seed))),
      shareSink: (name, content, msg) async => shared?.add(name),
    );

Future<AppServices> appWith(LedgerController ledger) async => AppServices.create(
      engine: FakeEngine(),
      prefs: memoryPreferences(),
      saver: FolderSaver(Directory.systemTemp),
      dataDir: () async => Directory.systemTemp.path,
      workDir: () async => Directory.systemTemp,
      ledger: ledger,
    );

void main() {
  testWidgets('create a trip from the trips screen', (t) async {
    final ledger = phone(1);
    final s = await appWith(ledger);
    await w.pumpApp(t, s, home: const TripsScreen());
    await t.runAsync(ledger.init);
    await t.pumpAndSettle();
    expect(find.text('How it works'), findsOneWidget);

    await t.tap(find.byKey(const Key('newTrip')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tripName')), 'Goa 2026');
    await t.enterText(find.byKey(const Key('tripMyName')), 'Aarav');
    await t.tap(find.byKey(const Key('createTrip')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.byType(TripScreen), findsOneWidget);
    expect(find.text('Goa 2026'), findsOneWidget);
    expect(find.text('You are all settled'), findsOneWidget);
    expect(find.textContaining('Invite your group'), findsOneWidget);
  });

  testWidgets('invited friend joins, then approves an expense', (t) async {
    final aarav = phone(1);
    final riya = phone(2);
    late String trip;
    late String dinnerId;
    await t.runAsync(() async {
      await aarav.init();
      await riya.init();
      trip = (await aarav.createTrip(name: 'Manali Trip', myName: 'Aarav')).id;
      await riya.importText(aarav.packet(trip).toFile());
    });
    final s = await appWith(riya);
    await w.pumpApp(t, s, home: TripScreen(tripId: trip));
    expect(find.text('You were invited to this trip'), findsOneWidget);
    await t.enterText(find.byKey(const Key('joinTripName')), 'Riya');
    await t.tap(find.byKey(const Key('joinTrip')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.text('Let the group know'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    // Aarav learns Riya joined, adds dinner for both, and shares it.
    await t.runAsync(() async {
      await aarav.importText(riya.packet(trip).toFile());
      final e = await aarav.addExpense(trip,
          title: 'Dinner', amount: 100000, paidBy: aarav.myId, shares: equalSplit(100000, [aarav.myId, riya.myId]));
      dinnerId = e.id;
      await riya.importText(aarav.packet(trip).toFile());
    });
    await t.pumpAndSettle();
    expect(find.text('Needs your approval (1)'), findsOneWidget);
    expect(find.textContaining('your share ₹500'), findsOneWidget);
    expect(find.text('1/2 approved'), findsOneWidget);

    await t.ensureVisible(find.byKey(Key('approve-$dinnerId')));
    await t.tap(find.byKey(Key('approve-$dinnerId')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.textContaining('Needs your approval'), findsNothing);
    expect(find.text('Agreed ✓'), findsOneWidget);
    expect(find.text('You owe'), findsOneWidget);
    expect(find.text('₹500'), findsWidgets);
    expect(find.textContaining('You pay'), findsOneWidget);
  });

  testWidgets('add expense validates and creates a pending entry', (t) async {
    final shared = <String>[];
    final ledger = phone(1, shared: shared);
    late String trip;
    await t.runAsync(() async {
      await ledger.init();
      trip = (await ledger.createTrip(name: 'Trip', myName: 'Aarav')).id;
    });
    final s = await appWith(ledger);
    await w.pumpApp(t, s, home: TripScreen(tripId: trip));
    await t.tap(find.byKey(const Key('addExpense')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('saveExpense')));
    await t.pump();
    expect(find.text('Add what it was for'), findsOneWidget);
    await t.enterText(find.byKey(const Key('expenseTitle')), 'Fuel');
    await t.enterText(find.byKey(const Key('expenseAmount')), '12.345');
    await t.tap(find.byKey(const Key('saveExpense')));
    await t.pump();
    expect(find.textContaining('Enter an amount'), findsOneWidget);
    await t.enterText(find.byKey(const Key('expenseAmount')), '1,200');
    await t.tap(find.byKey(const Key('saveExpense')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.text('Share with the group?'), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Share')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(shared, ['Trip.ldtrip']);
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('₹1,200'), findsWidgets);
    // Solo trip: the only person involved is the author → agreed immediately.
    expect(find.text('Agreed ✓'), findsOneWidget);
  });
}
