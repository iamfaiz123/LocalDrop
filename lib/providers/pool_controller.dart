import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/device_library.dart';
import '../services/preferences.dart';
import '../services/upload_manager.dart';

class _Decision {
  final DeviceAsset asset;
  final bool shared;
  final UploadTask? task;
  const _Decision(this.asset, this.shared, this.task);
}

/// "Drop to pool": review the phone's own photos and videos one at a time
/// (swipe right = send to the pool, left = skip) or pick several in a grid.
/// Decisions are remembered per session so reviewed items don't come back.
class PoolController extends ChangeNotifier {
  final DeviceLibrary library;
  final Preferences prefs;
  final UploadManager uploads;

  PoolController({required this.library, required this.prefs, required this.uploads});

  static const _pageSize = 120;
  static const _deckTarget = 24;

  String? _sessionId;
  LibraryAccess? access;
  bool loading = false;
  String? error;
  String? notice;

  final List<DeviceAsset> deck = [];
  final Set<String> shared = {};
  final Set<String> skipped = {};
  int libraryCount = 0;
  int _nextPage = 0;
  bool _exhausted = false;
  final List<_Decision> _history = [];
  final _thumbs = <String, Future<Uint8List?>>{}; // insertion-ordered (LRU)
  Timer? _saveTimer;

  DeviceAsset? get current => deck.isEmpty ? null : deck.first;
  DeviceAsset? get next => deck.length > 1 ? deck[1] : null;
  bool get canUndo => _history.isNotEmpty;
  bool get done => !loading && deck.isEmpty && _exhausted;
  int get remaining => (libraryCount - shared.length - skipped.length).clamp(0, 1 << 31);
  bool get hasAccess => access == LibraryAccess.full || access == LibraryAccess.limited;

  /// Opens the pool for [sessionId]: asks for photo access and fills the deck.
  Future<void> open(String sessionId) async {
    if (_sessionId != sessionId) {
      _sessionId = sessionId;
      deck.clear();
      _history.clear();
      shared
        ..clear()
        ..addAll(await _loadSet('shared'));
      skipped
        ..clear()
        ..addAll(await _loadSet('skipped'));
    }
    await reload();
  }

  Future<void> reload() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      access = await library.requestAccess();
      deck.clear();
      _nextPage = 0;
      _exhausted = false;
      if (hasAccess) {
        libraryCount = await library.count();
        await _fill();
      }
    } on Exception catch (e) {
      error = 'Could not open your photos: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _fill() async {
    while (deck.length < _deckTarget && !_exhausted) {
      final page = await library.page(_nextPage++, _pageSize);
      if (page.length < _pageSize) _exhausted = true;
      final queued = deck.map((a) => a.id).toSet();
      deck.addAll(page.where((a) => !shared.contains(a.id) && !skipped.contains(a.id) && !queued.contains(a.id)));
    }
  }

  void _topUp() {
    if (deck.length < 8 && !_exhausted && !loading) {
      loading = true;
      _fill().whenComplete(() {
        loading = false;
        notifyListeners();
      });
    }
  }

  /// Swipe right: send the top card to the pool.
  Future<void> shareCurrent() async {
    final a = current;
    if (a == null) return;
    deck.removeAt(0);
    shared.add(a.id);
    final decision = _Decision(a, true, null);
    _history.add(decision);
    _trimHistory();
    _changed();
    final task = await _send(a);
    if (task == null) {
      shared.remove(a.id);
      _history.remove(decision);
    } else {
      _history[_history.indexOf(decision)] = _Decision(a, true, task);
    }
    _changed();
  }

  /// Swipe left: skip the top card (it won't be shown again this session).
  void skipCurrent() {
    final a = current;
    if (a == null) return;
    deck.removeAt(0);
    skipped.add(a.id);
    _history.add(_Decision(a, false, null));
    _trimHistory();
    _changed();
  }

  /// Undoes the last swipe. A share can only be undone before its upload
  /// has started; afterwards it is already in the pool.
  Future<bool> undo() async {
    if (_history.isEmpty) return false;
    final last = _history.last;
    if (last.shared) {
      final t = last.task;
      if (t != null && !(t.state == TransferState.queued || t.state == TransferState.preparing || t.state == TransferState.paused)) {
        notice = 'Already sent to the pool. Delete it from the shared gallery if needed.';
        notifyListeners();
        return false;
      }
      if (t != null) await uploads.cancel(t);
      shared.remove(last.asset.id);
    } else {
      skipped.remove(last.asset.id);
    }
    _history.removeLast();
    deck.insert(0, last.asset);
    _changed();
    return true;
  }

  /// Grid selection: sends several items. Returns how many were queued.
  Future<int> sendMany(List<DeviceAsset> assets) async {
    var queued = 0;
    for (final a in assets.where((a) => !shared.contains(a.id))) {
      shared.add(a.id);
      deck.removeWhere((x) => x.id == a.id);
      if (await _send(a) != null) {
        queued++;
      } else {
        shared.remove(a.id);
      }
    }
    _changed();
    return queued;
  }

  /// Library page for the grid view (all items, decided ones included).
  Future<List<DeviceAsset>> gridPage(int page) => library.page(page, 90);

  Future<UploadTask?> _send(DeviceAsset a) async {
    try {
      final f = await library.original(a);
      final tasks = await uploads.addFiles([(path: f.path, name: f.name, isVideo: a.isVideo)]);
      return tasks.isEmpty ? null : tasks.first;
    } on Exception catch (e) {
      notice = e is DeviceLibraryException ? e.message : 'Could not read this item: $e';
      notifyListeners();
      return null;
    }
  }

  void _trimHistory() {
    if (_history.length > 50) _history.removeAt(0);
  }

  /// Cached thumbnail future (keeps ~80 recent ones in memory).
  Future<Uint8List?> thumbnail(DeviceAsset a, int size) {
    final key = '${a.id}@$size';
    final hit = _thumbs.remove(key);
    final f = hit ?? library.thumbnail(a, size);
    _thumbs[key] = f;
    while (_thumbs.length > 80) {
      _thumbs.remove(_thumbs.keys.first);
    }
    return f;
  }

  void clearNotice() {
    notice = null;
  }

  void _changed() {
    _topUp();
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<List<String>> _loadSet(String kind) async {
    final raw = await prefs.getRaw('pool.$_sessionId.$kind');
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _save() async {
    final sid = _sessionId;
    if (sid == null) return;
    await prefs.setRaw('pool.$sid.shared', jsonEncode(shared.toList()));
    await prefs.setRaw('pool.$sid.skipped', jsonEncode(skipped.toList()));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
