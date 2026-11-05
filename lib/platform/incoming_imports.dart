import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Trip expense updates opened from WhatsApp/Files (Android intents, iOS
/// document opening). Native code pings; we pull the pending content.
class IncomingImports {
  static const _channel = MethodChannel('app.localdrop/import');
  final _controller = StreamController<String>.broadcast();
  bool _started = false;

  Stream<String> get stream => _controller.stream;

  void start() {
    if (_started || !(Platform.isAndroid || Platform.isIOS)) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') await _pull();
    });
    _pull(); // something may have arrived before Dart was ready
  }

  Future<void> _pull() async {
    try {
      final text = await _channel.invokeMethod<String>('takePending');
      if (text != null && text.isNotEmpty) _controller.add(text);
    } on MissingPluginException {
      // not available
    } on PlatformException {
      // ignore
    }
  }
}
