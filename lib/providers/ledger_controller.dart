import 'package:flutter/foundation.dart';

import '../ledger/codec.dart';
import '../ledger/event.dart';
import '../ledger/identity.dart';
import '../ledger/ledger_store.dart';
import '../ledger/money.dart';
import '../ledger/trip_state.dart';

class ImportResult {
  final String? tripId;
  final String tripName;
  final int added;
  final int rejected;
  final bool needsJoin;
  const ImportResult({this.tripId, this.tripName = '', this.added = 0, this.rejected = 0, this.needsJoin = false});
  bool get found => tripId != null;
}

/// Shared trip expenses without a server.
///
/// Every action creates a signed entry on this phone. Phones exchange their
/// entries (WhatsApp, any messenger, or a pasted code); each phone verifies
/// signatures, merges, and derives the same balances. An expense only counts
/// once the payer and everyone in its split have approved it.
class LedgerController extends ChangeNotifier {
  final LedgerStore store;
  final KeyStore keys;
  final Future<void> Function(String fileName, String fileContent, String message)? shareSink;

  LedgerController({required this.store, required this.keys, this.shareSink});

  Identity? _me;
  final Map<String, List<LedgerEvent>> _events = {};
  final Map<String, TripState> _states = {};
  bool ready = false;

  String get myId => _me?.publicKeyHex ?? '';

  List<TripState> get trips => _states.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  TripState? trip(String id) => _states[id];
  int get pendingCount => _states.values.fold(0, (n, t) => n + t.pendingFor(myId).length);

  Future<void> init() async {
    if (ready) return;
    _me = await loadOrCreateIdentity(keys);
    for (final id in await store.tripIds()) {
      _events[id] = await store.load(id);
      _rebuild(id);
    }
    ready = true;
    notifyListeners();
  }

  void _rebuild(String tripId) {
    final s = TripState.build(tripId, _events[tripId] ?? const []);
    if (s == null) {
      _states.remove(tripId);
    } else {
      _states[tripId] = s;
    }
  }

  List<String> _heads(String tripId) {
    final evs = _events[tripId] ?? const [];
    final referenced = {for (final e in evs) ...e.prev};
    final heads = evs.where((e) => !referenced.contains(e.id)).map((e) => e.id).toList()..sort();
    return heads.length > 6 ? heads.sublist(heads.length - 6) : heads;
  }

  Future<LedgerEvent> _append(String tripId, String type, Map<String, dynamic> body) async {
    final e = await LedgerEvent.create(_me!, trip: tripId, type: type, body: body, prev: _heads(tripId));
    (_events[tripId] ??= []).add(e);
    await store.save(tripId, _events[tripId]!);
    _rebuild(tripId);
    notifyListeners();
    return e;
  }

  // ------------------------------------------------------------- actions

  Future<TripState> createTrip({required String name, required String myName, String currency = 'INR'}) async {
    final g = await LedgerEvent.create(_me!, trip: '', type: EventType.tripCreate, body: {
      'name': name.trim(),
      'currency': currency,
      'creator_name': myName.trim(),
    });
    _events[g.id] = [g];
    await store.save(g.id, _events[g.id]!);
    _rebuild(g.id);
    notifyListeners();
    return _states[g.id]!;
  }

  Future<void> join(String tripId, String myName) async {
    await _append(tripId, EventType.memberJoin, {'name': myName.trim()});
  }

  Future<LedgerEvent> addExpense(
    String tripId, {
    required String title,
    required int amount,
    required String paidBy,
    required Map<String, int> shares,
    int? date,
  }) {
    final total = shares.values.fold(0, (a, b) => a + b);
    if (total != amount) throw ArgumentError('Shares must add up to the amount');
    return _append(tripId, EventType.expenseAdd, {
      'title': title.trim(),
      'amount': amount,
      'paid_by': paidBy,
      'shares': {for (final e in shares.entries) if (e.value > 0) e.key: e.value},
      'date': date ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> approve(String tripId, String proposalId) => _append(tripId, EventType.approve, {'target': proposalId});

  Future<void> reject(String tripId, String proposalId, String reason) =>
      _append(tripId, EventType.reject, {'target': proposalId, 'reason': reason});

  Future<void> removeExpense(String tripId, String expenseId, String reason) =>
      _append(tripId, EventType.expenseVoid, {'target': expenseId, 'reason': reason});

  Future<void> recordPayment(String tripId, {required String from, required String to, required int amount, String note = ''}) =>
      _append(tripId, EventType.paymentAdd, {'from': from, 'to': to, 'amount': amount, 'note': note});

  Future<void> deleteTripFromThisPhone(String tripId) async {
    _events.remove(tripId);
    _states.remove(tripId);
    await store.delete(tripId);
    notifyListeners();
  }

  // ------------------------------------------------------------- sync

  /// Merges entries from a shared file or pasted WhatsApp text. Entries with
  /// a wrong signature or a forged id are dropped.
  Future<ImportResult> importText(String text) async {
    final packets = SyncPacket.parseAll(text);
    if (packets.isEmpty) return const ImportResult();
    ImportResult? result;
    for (final p in packets) {
      final known = {for (final e in _events[p.tripId] ?? const <LedgerEvent>[]) e.id};
      var added = 0, rejected = 0;
      final fresh = <LedgerEvent>[];
      for (final e in p.events) {
        if (known.contains(e.id) || e.tripId != p.tripId) continue;
        if (await e.verify()) {
          fresh.add(e);
          known.add(e.id);
          added++;
        } else {
          rejected++;
        }
      }
      if (fresh.isNotEmpty) {
        (_events[p.tripId] ??= []).addAll(fresh);
        await store.save(p.tripId, _events[p.tripId]!);
        _rebuild(p.tripId);
      }
      final s = _states[p.tripId];
      result = ImportResult(
        tripId: s == null ? null : p.tripId,
        tripName: s?.name ?? p.tripName,
        added: added,
        rejected: rejected,
        needsJoin: s != null && !s.isMember(myId),
      );
    }
    notifyListeners();
    return result ?? const ImportResult();
  }

  SyncPacket packet(String tripId) => SyncPacket(tripId, _states[tripId]?.name ?? 'Trip', List.of(_events[tripId] ?? const []));

  /// Human-readable WhatsApp message + attached `.ldtrip` file.
  String shareMessage(String tripId, {String? headline}) {
    final s = _states[tripId]!;
    final p = packet(tripId);
    final code = p.toCode();
    final lines = <String>[
      headline ?? '💸 ${s.name} expenses update',
      'Total so far: ${formatMoney(s.totalSpent, s.currency)}',
      for (final e in s.expenses.take(3))
        '• ${e.title}: ${formatMoney(e.amount, s.currency)} paid by ${s.nameOf(e.paidBy)}'
            '${e.status == ProposalStatus.pending ? ' (needs approval)' : ''}',
      '',
      'Open the attached file with LocalDrop to approve and stay in sync.',
      // Short enough for one message? Then also include the paste-able code.
      if (code.length <= 6000) ...['', 'Or copy this message and tap “Paste from WhatsApp” in LocalDrop:', code],
    ];
    return lines.join('\n');
  }

  String fileName(String tripId) {
    final n = (_states[tripId]?.name ?? 'trip').replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return '${n.isEmpty ? 'trip' : n}.ldtrip';
  }

  Future<void> share(String tripId, {String? headline}) async {
    final sink = shareSink;
    if (sink == null) return;
    await sink(fileName(tripId), packet(tripId).toFile(), shareMessage(tripId, headline: headline));
  }
}
