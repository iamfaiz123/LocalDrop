import 'dart:io';

import 'package:flutter/services.dart';

/// Platform-specific functionality implemented in Kotlin (Android) and
/// Swift (iOS). See `android/app/src/main/kotlin/.../MainActivity.kt` and
/// `ios/Runner/AppDelegate.swift`.
class NativeBridge {
  static const _channel = MethodChannel('app.localdrop/native');

  const NativeBridge();

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  /// Keeps the host process alive while a session runs (Android foreground
  /// service; on iOS a background task that buys limited extra time).
  /// [resumeConfig] (engine config JSON) lets Android restart the server by
  /// itself if the OS kills and recreates the process while the app is closed.
  Future<void> startHostingService(String sessionName, {String? resumeConfig}) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('startHosting', {'title': sessionName, 'config': resumeConfig});
    } on MissingPluginException {
      // Not available in tests / unsupported platforms.
    }
  }

  Future<void> stopHostingService() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('stopHosting');
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> keepScreenOn(bool on) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('keepScreenOn', {'on': on});
    } on MissingPluginException {
      // ignore
    }
  }

  /// JPEG thumbnail of a local video or image file (handles HEIC), or null.
  Future<Uint8List?> thumbnail(String path, {required bool video, int maxSize = 480}) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {'path': path, 'video': video, 'maxSize': maxSize});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
