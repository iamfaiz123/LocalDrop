import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../models/models.dart';

class EngineException implements Exception {
  final String message;
  const EngineException(this.message);
  @override
  String toString() => message;
}

/// Options for a new or resumed host session (mirrors the engine's
/// `EngineConfig`). Concurrency and sizes are configurable.
class EngineConfig {
  final String dataDir;
  final String sessionName;
  final String hostName;
  final int port;
  final int pinLength;
  final bool requireApproval;
  final bool keepMediaOnEnd;
  final int chunkSizeMiB;
  final int maxConcurrentUploads;
  final String? resumeSessionId;

  const EngineConfig({
    required this.dataDir,
    this.sessionName = '',
    this.hostName = '',
    this.port = 8080,
    this.pinLength = 6,
    this.requireApproval = false,
    this.keepMediaOnEnd = true,
    this.chunkSizeMiB = 8,
    this.maxConcurrentUploads = 6,
    this.resumeSessionId,
  });

  Map<String, dynamic> toJson() => {
        'data_dir': dataDir,
        'session_name': sessionName,
        'host_name': hostName,
        'port': port,
        'pin_length': pinLength,
        'require_approval': requireApproval,
        'keep_media_on_end': keepMediaOnEnd,
        'chunk_size': chunkSizeMiB * 1024 * 1024,
        'max_concurrent_uploads': maxConcurrentUploads,
        if (resumeSessionId != null) 'resume_session_id': resumeSessionId,
      };
}

class EngineStatus {
  final bool running;
  final bool ended;
  final List<String> urls;
  final String? joinUrl;
  final List<NetworkInterfaceInfo> addresses;
  final bool networkOk;

  /// The running session (incl. host credentials) — lets a re-opened app
  /// re-attach to a server that kept running in the background.
  final HostSession? session;
  const EngineStatus(this.running, this.ended, this.urls, this.joinUrl, this.addresses, this.networkOk, [this.session]);
}

/// Host-side engine lifecycle. Abstract so UI tests can use a fake.
abstract class EngineService {
  Future<HostSession> start(EngineConfig config);
  Future<void> stop();
  Future<EngineStatus> status();
  Future<List<NetworkInterfaceInfo>> interfaces();
  Future<List<StoredSession>> storedSessions(String dataDir);
  Future<void> deleteSession(String dataDir, String sessionId);
}

typedef _StrFn = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _Str2Fn = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _VoidFn = Pointer<Utf8> Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// Calls into the Rust engine (`liblocaldrop_engine`) through `dart:ffi`.
/// Every call runs on a background isolate so the UI thread never blocks.
class FfiEngineService implements EngineService {
  /// Overrides the library location (tests / desktop development).
  static String? libraryPathOverride = Platform.environment['LOCALDROP_ENGINE_LIB'];

  static DynamicLibrary _open() {
    final override = libraryPathOverride;
    if (override != null && override.isNotEmpty) return DynamicLibrary.open(override);
    if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('liblocaldrop_engine.so');
    if (Platform.isIOS) return DynamicLibrary.open('LocalDropEngine.framework/LocalDropEngine'); // vendored xcframework
    if (Platform.isMacOS) return DynamicLibrary.open('liblocaldrop_engine.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('localdrop_engine.dll');
    throw const EngineException('Hosting is not supported on this platform');
  }

  static Map<String, dynamic> _call(String fn, List<String> args) {
    final lib = _open();
    final free = lib.lookupFunction<_FreeNative, _FreeDart>('ld_string_free');
    final allocated = args.map((a) => a.toNativeUtf8()).toList();
    Pointer<Utf8> out;
    try {
      switch (args.length) {
        case 0:
          out = lib.lookupFunction<_VoidFn, _VoidFn>(fn)();
        case 1:
          out = lib.lookupFunction<_StrFn, _StrFn>(fn)(allocated[0]);
        default:
          out = lib.lookupFunction<_Str2Fn, _Str2Fn>(fn)(allocated[0], allocated[1]);
      }
    } finally {
      for (final p in allocated) {
        malloc.free(p);
      }
    }
    try {
      return jsonDecode(out.toDartString()) as Map<String, dynamic>;
    } finally {
      free(out);
    }
  }

  Future<Map<String, dynamic>> _run(String fn, [List<String> args = const []]) async {
    final override = libraryPathOverride;
    final Map<String, dynamic> r;
    try {
      r = await Isolate.run(() {
        libraryPathOverride = override;
        return _call(fn, args);
      });
    } on ArgumentError catch (e) {
      throw EngineException('The LocalDrop engine library could not be loaded: ${e.message}');
    }
    if (r['ok'] != true) throw EngineException(r['error'] as String? ?? 'Engine error');
    return r;
  }

  @override
  Future<HostSession> start(EngineConfig config) async {
    final r = await _run('ld_engine_start', [jsonEncode(config.toJson())]);
    return HostSession.fromJson(r['session'] as Map<String, dynamic>);
  }

  @override
  Future<void> stop() async => _run('ld_engine_stop');

  @override
  Future<EngineStatus> status() async {
    final r = await _run('ld_engine_status');
    return EngineStatus(
      r['running'] == true,
      r['ended'] == true,
      (r['urls'] as List?)?.cast<String>() ?? const [],
      r['join_url'] as String?,
      ((r['addresses'] as List?) ?? const []).map((e) => NetworkInterfaceInfo.fromJson(e as Map<String, dynamic>)).toList(),
      r['network_ok'] == true,
      r['session'] is Map<String, dynamic> ? HostSession.fromJson(r['session'] as Map<String, dynamic>) : null,
    );
  }

  @override
  Future<List<NetworkInterfaceInfo>> interfaces() async {
    final r = await _run('ld_network_interfaces');
    return ((r['interfaces'] as List?) ?? const [])
        .map((e) => NetworkInterfaceInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<StoredSession>> storedSessions(String dataDir) async {
    final r = await _run('ld_list_sessions', [dataDir]);
    return ((r['sessions'] as List?) ?? const []).map((e) => StoredSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> deleteSession(String dataDir, String sessionId) async => _run('ld_delete_session', [dataDir, sessionId]);
}
