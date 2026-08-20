import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'citiride_pin_hasher.dart';

/// Encrypted on-device storage for wallet PIN / passcode hashes.
class WalletSecretVault {
  WalletSecretVault._();

  static final WalletSecretVault instance = WalletSecretVault._();

  static const transactionPinKey = 'citiride.wallet.transactionPin.v2';
  static const passcodeKey = 'citiride.wallet.passcode.v2';

  /// Legacy plaintext SharedPreferences keys (migrated then deleted).
  static const _legacyTransactionPinKey = 'citiride.wallet.transactionPin';
  static const _legacyPasscodeKey = 'citiride.wallet.passcode';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<bool> hasSecret(String key) async {
    final value = await _storage.read(key: key);
    return value != null && value.isNotEmpty;
  }

  Future<void> saveSecret({
    required String key,
    required String plaintext,
  }) async {
    final encoded = CitiridePinHasher.hash(plaintext);
    await _storage.write(key: key, value: encoded);
  }

  Future<bool> verifySecret({
    required String key,
    required String plaintext,
  }) async {
    final stored = await _storage.read(key: key);
    if (stored == null || stored.isEmpty) {
      return false;
    }
    return CitiridePinHasher.verify(plaintext, stored);
  }

  Future<void> deleteSecret(String key) async {
    await _storage.delete(key: key);
  }

  /// Moves any leftover plaintext SharedPreferences secrets into secure storage.
  Future<void> migrateLegacyPlaintextSecrets() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final legacyPin = prefs.getString(_legacyTransactionPinKey);
      if (legacyPin != null && legacyPin.length == 4) {
        final alreadySecured = await hasSecret(transactionPinKey);
        if (!alreadySecured) {
          await saveSecret(key: transactionPinKey, plaintext: legacyPin);
        }
        await prefs.remove(_legacyTransactionPinKey);
      }

      final legacyPasscode = prefs.getString(_legacyPasscodeKey);
      if (legacyPasscode != null && legacyPasscode.isNotEmpty) {
        final alreadySecured = await hasSecret(passcodeKey);
        if (!alreadySecured) {
          await saveSecret(key: passcodeKey, plaintext: legacyPasscode);
        }
        await prefs.remove(_legacyPasscodeKey);
      }
    } on Object {
      // Migration must never block app start.
    }
  }
}
