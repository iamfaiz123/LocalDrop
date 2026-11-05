import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/api_client.dart';

enum MediaFilter { all, photos, videos, favorites }

/// Shared gallery state: paginated media, filters, selection, favourites
/// and real-time updates.
class GalleryController extends ChangeNotifier {
  ApiClient? _api;
  String? _meId;
  bool _isHost = false;

  final List<MediaItem> items = [];
  int total = 0;
  int? nextOffset = 0;
  bool loading = false;
  bool loadedOnce = false;
  String? error;

  MediaFilter filter = MediaFilter.all;
  String? uploaderId;
  bool ascending = false;
  final Set<String> selected = {};
  bool selectMode = false;
  int _generation = 0;
  static const pageSize = 60;

  ApiClient? get api => _api;
  bool get hasMore => nextOffset != null;
  bool get isEmpty => loadedOnce && items.isEmpty;

  void attach(ApiClient api, {required String meId, required bool isHost}) {
    _api = api;
    _meId = meId;
    _isHost = isHost;
    refresh();
  }

  void detach() {
    _api = null;
    items.clear();
    selected.clear();
    selectMode = false;
    total = 0;
    nextOffset = 0;
    loadedOnce = false;
    error = null;
    notifyListeners();
  }

  /// Test hook: shows [list] without contacting a server.
  @visibleForTesting
  void debugShow(ApiClient api, List<MediaItem> list, {required String meId, bool isHost = false, String? error}) {
    _api = api;
    _meId = meId;
    _isHost = isHost;
    items
      ..clear()
      ..addAll(list);
    total = list.length;
    nextOffset = null;
    loadedOnce = true;
    this.error = error;
    notifyListeners();
  }

  bool canDelete(MediaItem m) => _isHost || m.uploader.id == _meId;
  bool isMine(MediaItem m) => m.uploader.id == _meId;

  Future<void> refresh() async {
    _generation++;
    items.clear();
    selected.clear();
    nextOffset = 0;
    loadedOnce = false;
    loading = false;
    notifyListeners();
    await loadMore();
  }

  Future<void> loadMore() async {
    final api = _api;
    final offset = nextOffset;
    if (api == null || loading || offset == null) return;
    final gen = _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await api.listMedia(
        offset: offset,
        limit: pageSize,
        kind: switch (filter) { MediaFilter.photos => 'photo', MediaFilter.videos => 'video', _ => null },
        favorites: filter == MediaFilter.favorites,
        uploader: uploaderId,
        ascending: ascending,
      );
      if (gen != _generation) return;
      final known = items.map((m) => m.id).toSet();
      items.addAll(page.items.where((m) => !known.contains(m.id)));
      total = page.total;
      nextOffset = page.nextOffset;
      loadedOnce = true;
    } on ApiException catch (e) {
      if (gen == _generation) error = e.message;
    } finally {
      if (gen == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void setFilter(MediaFilter f) {
    if (filter == f) return;
    filter = f;
    refresh();
  }

  void setUploader(String? id) {
    uploaderId = id;
    refresh();
  }

  void toggleOrder() {
    ascending = !ascending;
    refresh();
  }

  bool _matches(MediaItem m) {
    if (filter == MediaFilter.photos && m.isVideo) return false;
    if (filter == MediaFilter.videos && !m.isVideo) return false;
    if (filter == MediaFilter.favorites && !m.favorite) return false;
    if (uploaderId != null && m.uploader.id != uploaderId) return false;
    return true;
  }

  void handleEvent(ServerEvent e) {
    switch (e.type) {
      case 'media_uploaded':
        final m = MediaItem.fromJson(e.data);
        if (_matches(m) && !items.any((x) => x.id == m.id)) {
          total++;
          if (!ascending) {
            items.insert(0, m);
          } else if (nextOffset == null) {
            items.add(m);
          }
          notifyListeners();
        }
      case 'media_updated':
        final m = MediaItem.fromJson(e.data);
        final i = items.indexWhere((x) => x.id == m.id);
        if (i >= 0) {
          items[i] = m.copyWith(favorite: items[i].favorite);
          notifyListeners();
        }
      case 'media_deleted':
        final id = e.data['id'] as String?;
        final before = items.length;
        items.removeWhere((x) => x.id == id);
        if (items.length != before) {
          total = (total - 1).clamp(0, 1 << 31);
          selected.remove(id);
          notifyListeners();
        }
      case 'resync':
        refresh();
    }
  }

  // ------------------------------------------------------------ selection
  void startSelection([String? id]) {
    selectMode = true;
    if (id != null) selected.add(id);
    notifyListeners();
  }

  void toggleSelected(String id) {
    if (!selected.remove(id)) selected.add(id);
    notifyListeners();
  }

  void selectAll() {
    if (selected.length == items.length) {
      selected.clear();
    } else {
      selected.addAll(items.map((m) => m.id));
    }
    notifyListeners();
  }

  void endSelection() {
    selectMode = false;
    selected.clear();
    notifyListeners();
  }

  List<MediaItem> get selectedItems => items.where((m) => selected.contains(m.id)).toList();

  // ------------------------------------------------------------ actions
  Future<void> toggleFavorite(MediaItem m) async {
    final api = _api;
    if (api == null) return;
    final next = !m.favorite;
    _replace(m.copyWith(favorite: next));
    try {
      await api.setFavorite(m.id, next);
      if (filter == MediaFilter.favorites && !next) {
        items.removeWhere((x) => x.id == m.id);
        total = (total - 1).clamp(0, 1 << 31);
        notifyListeners();
      }
    } on ApiException {
      _replace(m);
      rethrow;
    }
  }

  void _replace(MediaItem m) {
    final i = items.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      items[i] = m;
      notifyListeners();
    }
  }

  /// Deletes items the user may delete. Returns (deleted, skipped, failed).
  Future<(int, int, int)> delete(List<MediaItem> list) async {
    final api = _api;
    if (api == null) return (0, list.length, 0);
    var deleted = 0, failed = 0;
    final allowed = list.where(canDelete).toList();
    for (final m in allowed) {
      try {
        await api.deleteMedia(m.id);
        deleted++;
        if (items.any((x) => x.id == m.id)) {
          items.removeWhere((x) => x.id == m.id);
          total = (total - 1).clamp(0, 1 << 31);
        }
        selected.remove(m.id);
      } on ApiException {
        failed++;
      }
    }
    notifyListeners();
    return (deleted, list.length - allowed.length, failed);
  }
}
