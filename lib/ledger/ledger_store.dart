import 'dart:convert';
import 'dart:io';

import 'event.dart';

/// Persists each trip's signed entries on this device only.
abstract class LedgerStore {
  Future<List<String>> tripIds();
  Future<List<LedgerEvent>> load(String tripId);
  Future<void> save(String tripId, List<LedgerEvent> events);
  Future<void> delete(String tripId);
}

class FileLedgerStore implements LedgerStore {
  final Future<Directory> Function() root;
  FileLedgerStore(this.root);

  Future<Directory> _dir() async {
    final d = Directory('${(await root()).path}/ledger');
    await d.create(recursive: true);
    return d;
  }

  bool _validId(String id) => RegExp(r'^[0-9a-f]{64}$').hasMatch(id);

  @override
  Future<List<String>> tripIds() async {
    final d = await _dir();
    return [
      await for (final f in d.list())
        if (f is File && f.path.endsWith('.json')) f.uri.pathSegments.last.replaceAll('.json', ''),
    ].where(_validId).toList();
  }

  @override
  Future<List<LedgerEvent>> load(String tripId) async {
    if (!_validId(tripId)) return const [];
    final f = File('${(await _dir()).path}/$tripId.json');
    if (!await f.exists()) return const [];
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (j['events'] as List).map(LedgerEvent.tryParse).whereType<LedgerEvent>().toList();
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> save(String tripId, List<LedgerEvent> events) async {
    if (!_validId(tripId)) return;
    final d = await _dir();
    final tmp = File('${d.path}/$tripId.json.tmp');
    await tmp.writeAsString(jsonEncode({'events': events.map((e) => e.toJson()).toList()}), flush: true);
    await tmp.rename('${d.path}/$tripId.json');
  }

  @override
  Future<void> delete(String tripId) async {
    final f = File('${(await _dir()).path}/$tripId.json');
    if (await f.exists()) await f.delete();
  }
}

class MemoryLedgerStore implements LedgerStore {
  final data = <String, List<LedgerEvent>>{};
  @override
  Future<List<String>> tripIds() async => data.keys.toList();
  @override
  Future<List<LedgerEvent>> load(String tripId) async => List.of(data[tripId] ?? const []);
  @override
  Future<void> save(String tripId, List<LedgerEvent> events) async => data[tripId] = List.of(events);
  @override
  Future<void> delete(String tripId) async => data.remove(tripId);
}
