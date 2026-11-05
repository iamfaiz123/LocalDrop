import 'dart:convert';

import 'package:crypto/crypto.dart' as c;

import 'identity.dart';

/// Event types of the trip ledger.
abstract class EventType {
  static const tripCreate = 'trip.create';
  static const memberJoin = 'member.join';
  static const expenseAdd = 'expense.add';
  static const expenseVoid = 'expense.void';
  static const paymentAdd = 'payment.add';
  static const approve = 'approve';
  static const reject = 'reject';
}

/// Deterministic JSON (sorted keys, no whitespace) so every phone hashes
/// identical bytes.
String canonicalJson(Object? v) => jsonEncode(_canon(v));

Object? _canon(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(v[k])};
  }
  if (v is List) return v.map(_canon).toList();
  return v;
}

/// One signed, content-addressed ledger entry.
///
/// `id` = SHA-256 of the canonical unsigned fields; `sig` = Ed25519 signature
/// of `id` by `author`. Changing any field changes the id and invalidates the
/// signature, so entries cannot be altered or forged. `prev` lists the entries
/// the author had seen, linking the history like a chain.
class LedgerEvent {
  final String id;
  final String trip;
  final String author;
  final int ts;
  final String type;
  final Map<String, dynamic> body;
  final List<String> prev;
  final String sig;

  const LedgerEvent({
    required this.id,
    required this.trip,
    required this.author,
    required this.ts,
    required this.type,
    required this.body,
    required this.prev,
    required this.sig,
  });

  static Map<String, dynamic> _unsigned(String trip, String author, int ts, String type, Map<String, dynamic> body, List<String> prev) =>
      {'v': 1, 'trip': trip, 'author': author, 'ts': ts, 'type': type, 'body': body, 'prev': prev};

  static String computeId(Map<String, dynamic> unsigned) => c.sha256.convert(utf8.encode(canonicalJson(unsigned))).toString();

  static Future<LedgerEvent> create(
    Identity me, {
    required String trip,
    required String type,
    required Map<String, dynamic> body,
    List<String> prev = const [],
    int? ts,
  }) async {
    final time = ts ?? DateTime.now().millisecondsSinceEpoch;
    final unsigned = _unsigned(trip, me.publicKeyHex, time, type, body, prev);
    final id = computeId(unsigned);
    return LedgerEvent(
      id: id,
      trip: trip,
      author: me.publicKeyHex,
      ts: time,
      type: type,
      body: body,
      prev: prev,
      sig: await me.sign(utf8.encode(id)),
    );
  }

  /// True when the id matches the content and the author's signature is valid.
  Future<bool> verify() async {
    if (computeId(_unsigned(trip, author, ts, type, body, prev)) != id) return false;
    return Identity.verify(utf8.encode(id), sig, author);
  }

  /// Trip this event belongs to (a trip's id is the id of its creating event).
  String get tripId => type == EventType.tripCreate ? id : trip;

  Map<String, dynamic> toJson() => {..._unsigned(trip, author, ts, type, body, prev), 'id': id, 'sig': sig};

  static LedgerEvent? tryParse(Object? j) {
    if (j is! Map) return null;
    try {
      return LedgerEvent(
        id: j['id'] as String,
        trip: j['trip'] as String,
        author: j['author'] as String,
        ts: (j['ts'] as num).toInt(),
        type: j['type'] as String,
        body: Map<String, dynamic>.from(j['body'] as Map),
        prev: (j['prev'] as List).cast<String>(),
        sig: j['sig'] as String,
      );
    } on Object {
      return null;
    }
  }
}
