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
    expect(find.textContaining('Invite your group'), findsOneWidget);
    expect(find.text('No plans yet'), findsOneWidget, reason: 'new trips open on the Plan tab');
    await t.tap(find.text('Expenses'));
    await t.pumpAndSettle();
    expect(find.text('You are all settled'), findsOneWidget);
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
    await w.pumpApp(t, s, home: TripScreen(tripId: trip, startOnPlan: false));
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
    expect(find.text('Expenses · 1 to approve'), findsOneWidget);
    expect(find.text('Needs your approval (1)'), findsOneWidget);
    expect(find.textContaining('your share ₹500'), findsOneWidget);
    expect(find.text('1/2 approved'), findsOneWidget);

    await t.ensureVisible(find.byKey(Key('approve-$dinnerId')));
    await t.tap(find.byKey(Key('approve-$dinnerId')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.textContaining('Needs your approval'), findsNothing);
    expect(find.text('Agreed'), findsOneWidget);
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
    await w.pumpApp(t, s, home: TripScreen(tripId: trip, startOnPlan: false));
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
    expect(find.text('Agreed'), findsOneWidget);
  });

  testWidgets('invitee sees the plan before joining, then votes and joins an activity', (t) async {
    final aarav = phone(1);
    final riya = phone(2);
    late String trip, itemId;
    await t.runAsync(() async {
      await aarav.init();
      await riya.init();
      trip = (await aarav.createTrip(name: 'Manali Trip', myName: 'Aarav', destination: 'Manali', start: '2026-03-12', end: '2026-03-15')).id;
      itemId = (await aarav.addPlanItem(trip, title: 'Solang paragliding', day: DateTime(2026, 3, 13), time: '10:00', place: 'Solang')).id;
      await riya.importText(aarav.packet(trip).toFile());
    });
    final s = await appWith(riya);
    await w.pumpApp(t, s, home: TripScreen(tripId: trip));
    // Not a member yet: the plan is visible, voting is not.
    expect(find.text('You were invited to this trip'), findsOneWidget);
    expect(find.text('Solang paragliding'), findsOneWidget);
    expect(find.text('DAY 2'), findsOneWidget);
    expect(find.byKey(Key('yes-$itemId')), findsNothing);

    await t.enterText(find.byKey(const Key('joinTripName')), 'Riya');
    await t.tap(find.byKey(const Key('joinTrip')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Plan · 1 to vote'), findsOneWidget);
    expect(find.text('1/2 yes'), findsOneWidget);

    await t.ensureVisible(find.byKey(Key('yes-$itemId')));
    await t.tap(find.byKey(Key('yes-$itemId')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    // 2 of 2 is more than half → confirmed.
    expect(find.text('Confirmed'), findsOneWidget);
    await t.tap(find.byKey(Key('going-$itemId')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(find.text('I’m in'), findsOneWidget);
    expect(find.textContaining('2 going'), findsOneWidget);
  });

  testWidgets('add a plan item on a trip day and share it', (t) async {
    final shared = <String>[];
    final ledger = phone(1, shared: shared);
    late String trip;
    await t.runAsync(() async {
      await ledger.init();
      trip = (await ledger.createTrip(name: 'Goa', myName: 'Aarav', start: '2026-03-12', end: '2026-03-14')).id;
    });
    final s = await appWith(ledger);
    await w.pumpApp(t, s, home: TripScreen(tripId: trip));
    await t.tap(find.byKey(const Key('addPlan')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('savePlan')));
    await t.pump();
    expect(find.text('Say what the plan is'), findsOneWidget);
    await t.enterText(find.byKey(const Key('planTitle')), 'Beach shacks');
    await t.tap(find.text('Day 3 · 14 Mar'));
    await t.pump();
    await t.tap(find.byKey(const Key('savePlan')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Share')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(shared, ['Goa.ldtrip']);
    expect(find.text('Beach shacks'), findsOneWidget);
    expect(find.text('DAY 3'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget, reason: 'solo trip: 1 of 1 is a majority');
  });
}
