import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent settings: device identity, last used names and the
/// active session so the app can reconnect after being killed.
class Preferences {
  final SharedPreferencesAsync _p;
  Preferences([SharedPreferencesAsync? p]) : _p = p ?? SharedPreferencesAsync();

  Future<String> deviceId() async {
    var id = await _p.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _p.setString('device_id', id);
    }
    return id;
  }

  Future<String?> lastName() => _p.getString('last_name');
  Future<void> setLastName(String v) => _p.setString('last_name', v);

  /// Participant connection: base URL + token + session id.
  Future<({String base, String token, String sessionId})?> participantSession() async {
    final base = await _p.getString('p_base');
    final token = await _p.getString('p_token');
    final sid = await _p.getString('p_session');
    if (base == null || token == null || sid == null) return null;
    return (base: base, token: token, sessionId: sid);
  }

  Future<void> setParticipantSession(String base, String token, String sessionId) async {
    await _p.setString('p_base', base);
    await _p.setString('p_token', token);
    await _p.setString('p_session', sessionId);
  }

  Future<void> clearParticipantSession() async {
    await _p.remove('p_base');
    await _p.remove('p_token');
    await _p.remove('p_session');
  }

  /// Host session that was running when the app last stopped.
  Future<String?> hostSessionId() => _p.getString('h_session');
  Future<void> setHostSessionId(String? id) => id == null ? _p.remove('h_session') : _p.setString('h_session', id);

  /// Display name of the session we belong to (shown while reconnecting).
  Future<String?> activeSessionName() => _p.getString('active_name');
  Future<void> setActiveSessionName(String? v) => v == null ? _p.remove('active_name') : _p.setString('active_name', v);

  Future<String?> getRaw(String key) => _p.getString(key);
  Future<void> setRaw(String key, String value) => _p.setString(key, value);
}
