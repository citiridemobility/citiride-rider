import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Salted HMAC-SHA256 helpers for local wallet PIN / passcode verification.
///
/// Plaintext secrets are never persisted. Stored format: `<saltHex>.<hashHex>`.
abstract final class CitiridePinHasher {
  static const iterations = 48000;

  static String hash(String secret, {String? saltHex}) {
    final salt = saltHex == null || saltHex.isEmpty
        ? _randomSaltHex(16)
        : saltHex;
    final digest = _derive(secret, salt);
    return '$salt.${digest.toString()}';
  }

  static bool verify(String secret, String stored) {
    final parts = stored.split('.');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return false;
    }

    final expected = hash(secret, saltHex: parts[0]);
    return _constantTimeEquals(expected, stored);
  }

  static Digest _derive(String secret, String saltHex) {
    final saltBytes = utf8.encode(saltHex);
    List<int> block = utf8.encode(secret);
    final hmac = Hmac(sha256, saltBytes);

    // Stretching slows offline guessing if storage is ever extracted.
    var digest = hmac.convert(block);
    for (var i = 1; i < iterations; i++) {
      digest = hmac.convert(digest.bytes);
      block = digest.bytes;
    }
    return digest;
  }

  static String _randomSaltHex(int byteLength) {
    final random = Random.secure();
    final bytes = Uint8List(byteLength);
    for (var i = 0; i < byteLength; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
