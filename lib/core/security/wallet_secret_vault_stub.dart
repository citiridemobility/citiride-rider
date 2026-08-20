import 'citiride_pin_hasher.dart';

/// In-memory fallback for platforms without secure storage (e.g. some web builds).
class WalletSecretVault {
  WalletSecretVault._();

  static final WalletSecretVault instance = WalletSecretVault._();

  static const transactionPinKey = 'citiride.wallet.transactionPin.v2';
  static const passcodeKey = 'citiride.wallet.passcode.v2';

  final Map<String, String> _hashes = <String, String>{};

  Future<bool> hasSecret(String key) async {
    final value = _hashes[key];
    return value != null && value.isNotEmpty;
  }

  Future<void> saveSecret({
    required String key,
    required String plaintext,
  }) async {
    _hashes[key] = CitiridePinHasher.hash(plaintext);
  }

  Future<bool> verifySecret({
    required String key,
    required String plaintext,
  }) async {
    final stored = _hashes[key];
    if (stored == null || stored.isEmpty) {
      return false;
    }
    return CitiridePinHasher.verify(plaintext, stored);
  }

  Future<void> deleteSecret(String key) async {
    _hashes.remove(key);
  }

  Future<void> migrateLegacyPlaintextSecrets() async {}
}
