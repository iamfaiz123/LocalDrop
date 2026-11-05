import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Streams a file (or a prefix of it) through SHA-256 on a background
/// isolate. Never loads the file into memory.
Future<String> sha256OfFile(String path, {int? length}) => Isolate.run(() async {
      final input = File(path).openRead(0, length);
      final digest = await sha256.bind(input).first;
      return digest.toString();
    });
