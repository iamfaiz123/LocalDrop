import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localdrop/ledger/codec.dart';
import 'package:localdrop/ledger/event.dart';
import 'package:localdrop/ledger/identity.dart';
import 'package:localdrop/ledger/ledger_store.dart';
import 'package:localdrop/ledger/money.dart';
import 'package:localdrop/ledger/trip_state.dart';
import 'package:localdrop/providers/ledger_controller.dart';

/// One simulated phone.
Future<LedgerController> phone(int seed) async {
  final c = LedgerController(store: MemoryLedgerStore(), keys: MemoryKeyStore(base64.encode(List.filled(32, seed))));
  await c.init();
  return c;
}

/// "Send over WhatsApp": the receiver imports the sender's file.
Future<ImportResult> send(LedgerController from, LedgerController to, String tripId) => to.importText(from.packet(tripId).toFile());

void main() {
  late LedgerController aarav, riya, karan, meera;
  late String trip;

  setUp(() async {
    aarav = await phone(1);
    riya = await phone(2);
    karan = await phone(3);
    meera = await phone(4);
    trip = (await aarav.createTrip(name: 'Manali Trip', myName: 'Aarav')).id;
    for (final (p, n) in [(riya, 'Riya'), (karan, 'Karan'), (meera, 'Meera')]) {
      final r = await send(aarav, p, trip);
      expect(r.needsJoin, isTrue);
      await p.join(trip, n);
      await send(p, aarav, trip);
    }
    // Aarav shares to the group; everyone now knows everyone.
    for (final p in [riya, karan, meera]) {
      await send(aarav, p, trip);
    }
  });

  test('everyone sees the same members', () {
    for (final p in [aarav, riya, karan, meera]) {
      expect(p.trip(trip)!.members.values.map((m) => m.name).toSet(), {'Aarav', 'Riya', 'Karan', 'Meera'});
    }
  });

  test('an expense counts only after the payer and everyone in the split approve', () async {
    final ids = aarav.trip(trip)!.members.keys;
    final dinner = await aarav.addExpense(trip, title: 'Dinner', amount: 200000, paidBy: aarav.myId, shares: equalSplit(200000, ids));
    for (final p in [riya, karan, meera]) {
      await send(aarav, p, trip);
    }
    expect(riya.trip(trip)!.pendingFor(riya.myId).single.id, dinner.id);
    expect(riya.trip(trip)!.totalSpent, 0, reason: 'not agreed yet');

    await riya.approve(trip, dinner.id);
    await karan.approve(trip, dinner.id);
    await send(riya, aarav, trip);
    await send(karan, aarav, trip);
    var s = aarav.trip(trip)!;
    expect(s.expenses.single.status, ProposalStatus.pending);
    expect(s.expenses.single.waitingFor, {meera.myId});

    await meera.approve(trip, dinner.id);
    await send(meera, aarav, trip);
    s = aarav.trip(trip)!;
    expect(s.expenses.single.status, ProposalStatus.confirmed);
    expect(s.balances[aarav.myId], 150000);
    expect(s.balances[riya.myId], -50000);
    expect(s.settlements.length, 3);
    expect(s.settlements.every((x) => x.to == aarav.myId && x.amount == 50000), isTrue);

    // Gossip: Riya never heard from Karan or Meera directly, but one update from Aarav brings her up to date.
    await send(aarav, riya, trip);
    expect(riya.trip(trip)!.balances, s.balances);
  });

  test('a rejection blocks the expense; the payer can remove it', () async {
    final ids = [aarav.myId, riya.myId];
    final taxi = await riya.addExpense(trip, title: 'Taxi', amount: 90000, paidBy: riya.myId, shares: equalSplit(90000, ids));
    await send(riya, aarav, trip);
    await aarav.reject(trip, taxi.id, 'It was ₹700');
    await send(aarav, riya, trip);
    final s = riya.trip(trip)!;
    expect(s.expenses.single.status, ProposalStatus.rejected);
    expect(s.expenses.single.rejections[aarav.myId], 'It was ₹700');
    expect(s.totalSpent, 0);
  });

  test('removing an agreed expense needs everyone involved again', () async {
    final ids = [aarav.myId, karan.myId];
    final fuel = await aarav.addExpense(trip, title: 'Fuel', amount: 300000, paidBy: aarav.myId, shares: equalSplit(300000, ids));
    await send(aarav, karan, trip);
    await karan.approve(trip, fuel.id);
    await send(karan, aarav, trip);
    expect(aarav.trip(trip)!.totalSpent, 300000);

    await aarav.removeExpense(trip, fuel.id, 'Duplicate');
    var s = aarav.trip(trip)!;
    expect(s.expenses.single.effective, isTrue, reason: 'Karan has not agreed to the removal');
    final removal = s.expenses.single.removal!;
    await send(aarav, karan, trip);
    expect(karan.trip(trip)!.pendingFor(karan.myId).single.id, removal.id);
    await karan.approve(trip, removal.id);
    await send(karan, aarav, trip);
    s = aarav.trip(trip)!;
    expect(s.expenses.single.removed, isTrue);
    expect(s.totalSpent, 0);
  });

  test('repayments need the receiver to confirm', () async {
    final hotel = await aarav.addExpense(trip, title: 'Hotel', amount: 100000, paidBy: aarav.myId,
        shares: equalSplit(100000, [aarav.myId, meera.myId]));
    await send(aarav, meera, trip);
    await meera.approve(trip, hotel.id);
    await meera.recordPayment(trip, from: meera.myId, to: aarav.myId, amount: 50000, note: 'UPI');
    await send(meera, aarav, trip);
    var s = aarav.trip(trip)!;
    expect(s.balances[meera.myId], -50000, reason: 'payment not confirmed by Aarav yet');
    await aarav.approve(trip, s.payments.single.id);
    s = aarav.trip(trip)!;
    expect(s.balances[meera.myId], 0);
    expect(s.settlements, isEmpty);
  });

  test('tampered amounts and forged approvals are rejected on import', () async {
    final ids = [aarav.myId, riya.myId];
    final e = await aarav.addExpense(trip, title: 'Snacks', amount: 40000, paidBy: aarav.myId, shares: equalSplit(40000, ids));

    // Someone edits the amount inside the forwarded file.
    final j = aarav.packet(trip).toJson();
    final evs = (j['events'] as List).cast<Map<String, dynamic>>();
    final idx = evs.indexWhere((x) => x['id'] == e.id);
    evs[idx] = {
      ...evs[idx],
      'body': {...(evs[idx]['body'] as Map), 'amount': 4000000}
    };
    final r = await riya.importText(jsonEncode(j));
    expect(r.rejected, 1);
    expect(riya.trip(trip)!.expenses.where((x) => x.id == e.id), isEmpty);

    // Karan signs an approval but pretends to be Riya.
    final forged = await LedgerEvent.create(await Identity.fromSeed(List.filled(32, 3)),
        trip: trip, type: EventType.approve, body: {'target': e.id});
    final fake = LedgerEvent(
        id: forged.id, trip: trip, author: riya.myId, ts: forged.ts, type: forged.type, body: forged.body, prev: forged.prev, sig: forged.sig);
    expect(await fake.verify(), isFalse);
    final r2 = await aarav.importText(SyncPacket(trip, 'x', [fake]).toFile());
    expect(r2.rejected, 1);
    expect(aarav.trip(trip)!.expenses.single.approvals.contains(riya.myId), isFalse);
  });

  test('approvals by people not involved are ignored', () async {
    final e = await aarav.addExpense(trip, title: 'Coffee', amount: 20000, paidBy: aarav.myId,
        shares: equalSplit(20000, [aarav.myId, riya.myId]));
    await send(aarav, meera, trip);
    await meera.approve(trip, e.id); // Meera is not in the split
    await send(meera, aarav, trip);
    final s = aarav.trip(trip)!;
    expect(s.expenses.single.status, ProposalStatus.pending);
    expect(s.ignored, 1);
  });

  test('state is identical regardless of the order entries arrive', () async {
    final ids = aarav.trip(trip)!.members.keys;
    await aarav.addExpense(trip, title: 'Rafting', amount: 480000, paidBy: aarav.myId, shares: equalSplit(480000, ids));
    final events = aarav.packet(trip).events;
    final a = TripState.build(trip, events)!;
    final b = TripState.build(trip, events.reversed)!;
    final shuffled = List.of(events)..shuffle();
    final c = TripState.build(trip, shuffled)!;
    expect(b.balances, a.balances);
    expect(c.expenses.map((e) => e.id), a.expenses.map((e) => e.id));
  });

  test('WhatsApp message carries a pasteable code', () async {
    final msg = aarav.shareMessage(trip);
    expect(msg, contains('Manali Trip'));
    expect(msg, contains('LD1:'));
    final fresh = await phone(9);
    final r = await fresh.importText('Forwarded:\n$msg');
    expect(r.tripId, trip);
    expect(r.needsJoin, isTrue);
    expect(fresh.trip(trip)!.members.length, 4);
  });

  test('garbage input is handled', () async {
    expect((await aarav.importText('hello')).found, isFalse);
    expect((await aarav.importText('LD1:notbase64!!')).found, isFalse);
    expect(() => aarav.addExpense(trip, title: 'x', amount: 100, paidBy: aarav.myId, shares: {aarav.myId: 50}),
        throwsArgumentError);
  });

  test('money helpers', () {
    expect(parseMoney('500'), 50000);
    expect(parseMoney('1,234.5'), 123450);
    expect(parseMoney('0'), isNull);
    expect(parseMoney('12.345'), isNull);
    expect(formatMoney(123450, 'INR'), '₹1,234.50');
    expect(formatMoney(-50000, 'USD'), r'-$500');
    final split = equalSplit(1000, ['c', 'a', 'b']);
    expect(split.values.fold<int>(0, (a, b) => a + b), 1000);
    expect(split, {'a': 334, 'b': 333, 'c': 333});
  });
}
