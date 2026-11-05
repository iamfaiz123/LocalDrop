import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/models.dart';

/// Error returned by the engine (`{"error": {"code", "message"}}`) or a
/// network failure (`code == 'network'` / `'timeout'`).
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> details;
  const ApiException(this.status, this.code, this.message, [this.details = const {}]);

  bool get isNetwork => code == 'network' || code == 'timeout';
  bool get isAuth => status == 401 || code == 'removed' || code == 'blocked';
  bool get sessionEnded => code == 'session_ended';

  @override
  String toString() => message;
}

/// Thin client for the LocalDrop engine HTTP API. Used identically by the
/// host (against 127.0.0.1) and by participants (against the host's LAN IP).
class ApiClient {
  final Uri baseUri;
  String? token;
  final HttpClient _http;
  final Duration timeout;

  ApiClient(this.baseUri, {this.token, HttpClient? httpClient, this.timeout = const Duration(seconds: 15)})
      : _http = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 8)) {
    _http.idleTimeout = const Duration(seconds: 20);
    // LAN only: never route through a system proxy.
    _http.findProxy = (_) => 'DIRECT';
  }

  void close() => _http.close(force: true);

  Map<String, String> get authHeaders => token == null ? const {} : {'Authorization': 'Bearer $token'};

  Uri uri(String path, [Map<String, String>? query]) =>
      baseUri.replace(path: path, queryParameters: (query == null || query.isEmpty) ? null : query);

  String fileUrl(String mediaId, {bool download = false}) =>
      uri('/api/media/$mediaId/file', download ? {'download': '1'} : null).toString();
  String thumbnailUrl(MediaItem m) => uri('/api/media/${m.id}/thumbnail', {'v': m.sha256.substring(0, 8)}).toString();

  Future<HttpClientResponse> send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
    List<int>? bytes,
    ContentType? contentType,
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        final req = await _http.openUrl(method, uri(path, query)).timeout(timeout ?? this.timeout);
        // The retry never reuses a pooled keep-alive connection.
        if (attempt > 0) req.persistentConnection = false;
        authHeaders.forEach(req.headers.set);
        headers?.forEach(req.headers.set);
        if (json != null) {
          final body = utf8.encode(jsonEncode(json));
          req.headers.contentType = ContentType.json;
          req.contentLength = body.length;
          req.add(body);
        } else if (bytes != null) {
          req.headers.contentType = contentType ?? ContentType.binary;
          req.contentLength = bytes.length;
          req.add(bytes);
        }
        return await req.close().timeout(timeout ?? this.timeout);
      } on TimeoutException {
        throw ApiException(0, 'timeout', 'The host did not respond in time ($method $path)');
      } on SocketException catch (e) {
        if (attempt == 0 && isStaleConnection(e.osError?.message ?? e.message)) continue;
        throw ApiException(0, 'network', 'Cannot reach the host (${e.osError?.message ?? e.message})');
      } on HttpException catch (e) {
        if (attempt == 0 && isStaleConnection(e.message)) continue;
        throw ApiException(0, 'network', 'Connection problem: ${e.message}');
      } on OSError catch (e) {
        // Some connection failures surface as a bare OSError.
        if (attempt == 0 && isStaleConnection(e.message)) continue;
        throw ApiException(0, 'network', 'Cannot reach the host (${e.message})');
      } on IOException catch (e) {
        throw ApiException(0, 'network', 'Connection problem: $e');
      } on FormatException {
        throw const ApiException(0, 'bad_address', 'That address is not valid');
      }
    }
  }

  /// Errors that mean a reused keep-alive connection had already been closed
  /// by the host, so the request never reached it and is safe to send again.
  static bool isStaleConnection(String message) {
    final m = message.toLowerCase();
    return m.contains('broken pipe') ||
        m.contains('connection reset') ||
        m.contains('connection closed before full header') ||
        m.contains('connection closed while receiving data');
  }

  static Future<Map<String, dynamic>> decode(HttpClientResponse r) async {
    final text = await utf8.decodeStream(r);
    Map<String, dynamic> body = const {};
    if (text.isNotEmpty) {
      try {
        final v = jsonDecode(text);
        if (v is Map<String, dynamic>) body = v;
      } on FormatException {
        // fall through with an empty body
      }
    }
    if (r.statusCode >= 400) {
      final err = (body['error'] as Map?)?.cast<String, dynamic>() ?? const {};
      throw ApiException(
        r.statusCode,
        err['code'] as String? ?? 'http_${r.statusCode}',
        err['message'] as String? ?? 'Request failed (${r.statusCode})',
        err,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> getJson(String path, [Map<String, String>? query]) async =>
      decode(await send('GET', path, query: query));
  Future<Map<String, dynamic>> postJson(String path, [Object? body]) async =>
      decode(await send('POST', path, json: body ?? const {}));
  Future<Map<String, dynamic>> patchJson(String path, Object body) async => decode(await send('PATCH', path, json: body));
  Future<Map<String, dynamic>> deleteJson(String path) async => decode(await send('DELETE', path));

  // ---------------------------------------------------------- session
  Future<bool> health() async {
    try {
      final r = await getJson('/api/health');
      return r['ok'] == true;
    } on ApiException {
      return false;
    }
  }

  Future<SessionInfo> sessionInfo() async => SessionInfo.fromJson(await getJson('/api/session/info'));

  /// Joins and stores the returned token. Returns (participant, session).
  Future<(Participant, SessionInfo)> join({required String name, required String pin, String? deviceId}) async {
    final r = await postJson('/api/session/join', {'name': name, 'pin': pin, if (deviceId != null) 'device_id': deviceId});
    token = r['token'] as String;
    return (
      Participant.fromJson(r['participant'] as Map<String, dynamic>),
      SessionInfo.fromJson(r['session'] as Map<String, dynamic>),
    );
  }

  Future<(Participant, SessionInfo)> me() async {
    final r = await getJson('/api/session/me');
    return (
      Participant.fromJson(r['participant'] as Map<String, dynamic>),
      SessionInfo.fromJson(r['session'] as Map<String, dynamic>),
    );
  }

  Future<List<Participant>> participants() async {
    final r = await getJson('/api/session/participants');
    return (r['participants'] as List).map((e) => Participant.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> leave() => postJson('/api/session/leave');
  Future<Map<String, dynamic>> endSession({required bool deleteMedia}) =>
      postJson('/api/session/end', {'delete_media': deleteMedia});
  Future<SessionInfo> updateSettings(Map<String, Object> changes) async =>
      SessionInfo.fromJson(await patchJson('/api/session/settings', changes));
  Future<SessionStats> stats() async => SessionStats.fromJson(await getJson('/api/session/stats'));
  Future<StorageInfo> storage() async => StorageInfo.fromJson(await getJson('/api/storage/info'));
  Future<void> participantAction(String id, String action) => postJson('/api/participants/$id/$action');

  // ---------------------------------------------------------- media
  Future<MediaPage> listMedia({
    int offset = 0,
    int limit = 60,
    String? kind,
    String? uploader,
    bool favorites = false,
    bool ascending = false,
  }) async {
    final r = await getJson('/api/media', {
      'offset': '$offset',
      'limit': '$limit',
      if (kind != null) 'kind': kind,
      if (uploader != null) 'uploader': uploader,
      if (favorites) 'favorites': 'true',
      'order': ascending ? 'asc' : 'desc',
    });
    return MediaPage(
      (r['items'] as List).map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList(),
      (r['total'] as num).toInt(),
      (r['next_offset'] as num?)?.toInt(),
    );
  }

  Future<MediaItem> media(String id) async => MediaItem.fromJson(await getJson('/api/media/$id'));
  Future<void> deleteMedia(String id) => deleteJson('/api/media/$id');
  Future<void> setFavorite(String id, bool fav) async =>
      decode(await send(fav ? 'POST' : 'DELETE', '/api/media/$id/favorite', json: const {}));

  Future<void> putThumbnail(String mediaId, Uint8List jpeg) async {
    await decode(await send('PUT', '/api/media/$mediaId/thumbnail',
        bytes: jpeg, contentType: ContentType('image', 'jpeg'), timeout: const Duration(seconds: 30)));
  }

  // ---------------------------------------------------------- uploads
  Future<Map<String, dynamic>> createUpload(String filename, int size, {String? sha256}) =>
      postJson('/api/media/upload', {'filename': filename, 'size': size, if (sha256 != null) 'sha256': sha256});

  Future<Map<String, dynamic>> uploadStatus(String uploadId) => getJson('/api/uploads/$uploadId');

  /// Streams one chunk. [onProgress] reports bytes of this chunk sent so far.
  Future<Map<String, dynamic>> putChunk(
    String uploadId,
    int offset,
    Stream<List<int>> data,
    int length, {
    String? chunkSha256,
    void Function(int sent)? onProgress,
    void Function(HttpClientRequest req)? onRequest,
  }) async {
    try {
      final req = await _http.openUrl('PUT', uri('/api/uploads/$uploadId', {'offset': '$offset'})).timeout(timeout);
      onRequest?.call(req);
      authHeaders.forEach(req.headers.set);
      req.headers.contentType = ContentType.binary;
      req.contentLength = length;
      if (chunkSha256 != null) req.headers.set('x-chunk-sha256', chunkSha256);
      var sent = 0;
      await req.addStream(data.map((b) {
        sent += b.length;
        onProgress?.call(sent);
        return b;
      }));
      final res = await req.close().timeout(const Duration(minutes: 3));
      return await decode(res);
    } on TimeoutException {
      throw const ApiException(0, 'timeout', 'The host stopped responding');
    } on SocketException catch (e) {
      throw ApiException(0, 'network', 'Connection to the host was lost (${e.osError?.message ?? e.message})');
    } on HttpException catch (e) {
      throw ApiException(0, 'network', 'Upload interrupted: ${e.message}');
    } on OSError catch (e) {
      throw ApiException(0, 'network', 'Connection to the host was lost (${e.message})');
    } on IOException catch (e) {
      throw ApiException(0, 'network', 'Upload interrupted: $e');
    }
  }

  Future<Map<String, dynamic>> completeUpload(String uploadId, String sha256) async =>
      decode(await send('POST', '/api/uploads/$uploadId/complete',
          json: {'sha256': sha256}, timeout: const Duration(minutes: 10)));

  Future<void> cancelUpload(String uploadId) => deleteJson('/api/uploads/$uploadId');

  // ---------------------------------------------------------- downloads
  Future<Map<String, dynamic>> createExport(List<String> ids) => postJson('/api/media/download', {'ids': ids});

  /// Opens a (possibly ranged) GET for streaming downloads.
  Future<HttpClientResponse> openDownload(String path, {int from = 0, String? ifRange}) async {
    final res = await send('GET', path, headers: {
      if (from > 0) 'range': 'bytes=$from-',
      if (from > 0 && ifRange != null) 'if-range': ifRange,
    }, timeout: const Duration(seconds: 30));
    if (res.statusCode >= 400) await decode(res);
    return res;
  }

  Uri get webSocketUri => baseUri.replace(scheme: baseUri.scheme == 'https' ? 'wss' : 'ws', path: '/api/ws');
}
