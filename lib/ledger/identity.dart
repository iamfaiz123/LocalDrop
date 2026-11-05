import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// This phone's signing identity (Ed25519). The public key is the member id
/// in every trip ledger; the private key never leaves the device.
class Identity {
  final SimpleKeyPair _keyPair;
  final String publicKeyHex;
  Identity._(this._keyPair, this.publicKeyHex);

  static final _ed25519 = Ed25519();

  static Future<Identity> fromSeed(List<int> seed) async {
    final kp = await _ed25519.newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    return Identity._(kp, _hex(pub.bytes));
  }

  Future<String> sign(List<int> message) async {
    final s = await _ed25519.sign(message, keyPair: _keyPair);
    return base64Url.encode(s.bytes).replaceAll('=', '');
  }

  static Future<bool> verify(List<int> message, String signatureB64, String publicKeyHex) async {
    try {
      final sig = base64Url.decode(base64Url.normalize(signatureB64));
      final pub = _unhex(publicKeyHex);
      if (sig.length != 64 || pub.length != 32) return false;
      return await _ed25519.verify(
        message,
        signature: Signature(sig, publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
      );
    } on FormatException {
      return false;
    }
  }

  static String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  static List<int> _unhex(String s) {
    if (s.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(s)) throw const FormatException('bad hex');
    return [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];
  }
}

/// Where the private seed is kept.
abstract class KeyStore {
  Future<String?> readSeed();
  Future<void> writeSeed(String seedB64);
}

/// Keychain (iOS) / Keystore-backed storage (Android).
class SecureKeyStore implements KeyStore {
  static const _key = 'ledger_identity_seed';
  final FlutterSecureStorage _s;
  SecureKeyStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  @override
  Future<String?> readSeed() => _s.read(key: _key);
  @override
  Future<void> writeSeed(String seedB64) => _s.write(key: _key, value: seedB64);
}

class MemoryKeyStore implements KeyStore {
  String? seed;
  MemoryKeyStore([this.seed]);
  @override
  Future<String?> readSeed() async => seed;
  @override
  Future<void> writeSeed(String seedB64) async => seed = seedB64;
}

Future<Identity> loadOrCreateIdentity(KeyStore store) async {
  final existing = await store.readSeed();
  if (existing != null) return Identity.fromSeed(base64.decode(existing));
  final r = Random.secure();
  final seed = List<int>.generate(32, (_) => r.nextInt(256));
  await store.writeSeed(base64.encode(seed));
  return Identity.fromSeed(seed);
}
