import 'package:flutter/material.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.production();
  runApp(LocalDropApp(services: services));
  // Ads start after the UI is up and never delay or block the app (offline-first).
  WidgetsBinding.instance.addPostFrameCallback((_) => services.ads.initialize());
}
