import 'dart:convert';
import 'dart:io';

import 'event.dart';

/// What travels over WhatsApp (or any app): every signed entry of a trip.
/// Receivers merge it; duplicates are ignored, so resending is harmless.
class SyncPacket {
  final String tripId;
  final String tripName;
  final List<LedgerEvent> events;
  const SyncPacket(this.tripId, this.tripName, this.events);

  Map<String, dynamic> toJson() => {
        'format': 'localdrop-trip',
        'v': 1,
        'trip': tripId,
        'name': tripName,
        'events': events.map((e) => e.toJson()).toList(),
      };

  /// Readable file content (`.ldtrip`).
  String toFile() => jsonEncode(toJson());

  /// Compact text code for pasting: `LD1:` + base64url(gzip(json)).
  String toCode() => 'LD1:${base64Url.encode(gzip.encode(utf8.encode(toFile()))).replaceAll('=', '')}';

  static SyncPacket? _fromJson(Object? j) {
    if (j is! Map || j['format'] != 'localdrop-trip' || j['events'] is! List) return null;
    final events = (j['events'] as List).map(LedgerEvent.tryParse).whereType<LedgerEvent>().toList();
    final trip = j['trip'];
    if (trip is! String) return null;
    return SyncPacket(trip, (j['name'] as String?) ?? 'Trip', events);
  }

  /// Finds packets in a file's content or in pasted message text.
  static List<SyncPacket> parseAll(String text) {
    final out = <SyncPacket>[];
    final t = text.trim();
    if (t.startsWith('{')) {
      try {
        final p = _fromJson(jsonDecode(t));
        if (p != null) out.add(p);
      } on FormatException {
        // not JSON
      }
    }
    for (final m in RegExp(r'LD1:([A-Za-z0-9_-]+)').allMatches(text)) {
      try {
        final raw = utf8.decode(gzip.decode(base64Url.decode(base64Url.normalize(m.group(1)!))));
        final p = _fromJson(jsonDecode(raw));
        if (p != null) out.add(p);
      } on Object {
        // corrupted / truncated code
      }
    }
    return out;
  }
}
