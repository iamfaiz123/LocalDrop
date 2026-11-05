import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/models.dart';
import 'api_client.dart';

enum ConnectionStatus { connecting, connected, reconnecting, closed }

/// Keeps a WebSocket open to the engine with automatic reconnection and a
/// heartbeat, and exposes server events as a stream.
class RealtimeService {
  final ApiClient api;
  final _events = StreamController<ServerEvent>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  WebSocket? _ws;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;
  ConnectionStatus _current = ConnectionStatus.closed;

  RealtimeService(this.api);

  Stream<ServerEvent> get events => _events.stream;
  Stream<ConnectionStatus> get statusStream => _status.stream;
  ConnectionStatus get status => _current;

  void _set(ConnectionStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  Future<void> connect() async {
    _closed = false;
    _retry?.cancel();
    _set(_attempt == 0 ? ConnectionStatus.connecting : ConnectionStatus.reconnecting);
    try {
      final ws = await WebSocket.connect(
        api.webSocketUri.toString(),
        headers: api.authHeaders,
      ).timeout(const Duration(seconds: 8));
      if (_closed) {
        await ws.close();
        return;
      }
      _ws = ws;
      final reconnected = _attempt > 0;
      _attempt = 0;
      ws.pingInterval = const Duration(seconds: 20);
      _set(ConnectionStatus.connected);
      if (reconnected) _events.add(const ServerEvent('resync', {}, 0));
      ws.listen(
        (msg) {
          if (msg is! String || msg == 'pong') return;
          try {
            final j = jsonDecode(msg);
            if (j is Map<String, dynamic>) _events.add(ServerEvent.fromJson(j));
          } on FormatException {
            // ignore malformed frames
          }
        },
        onDone: _onDrop,
        onError: (_) => _onDrop(),
        cancelOnError: true,
      );
    } catch (_) {
      _onDrop();
    }
  }

  void _onDrop() {
    _ws = null;
    _ping?.cancel();
    if (_closed) {
      _set(ConnectionStatus.closed);
      return;
    }
    _attempt++;
    _set(ConnectionStatus.reconnecting);
    final delay = Duration(milliseconds: min(15000, 500 * pow(2, min(_attempt, 5)).toInt()));
    _retry = Timer(delay, connect);
  }

  /// Forces an immediate reconnect attempt (e.g. app returned to foreground).
  void reconnectNow() {
    if (_closed || _current == ConnectionStatus.connected) return;
    _retry?.cancel();
    connect();
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    await _ws?.close();
    _ws = null;
    _set(ConnectionStatus.closed);
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
    await _status.close();
  }
}
