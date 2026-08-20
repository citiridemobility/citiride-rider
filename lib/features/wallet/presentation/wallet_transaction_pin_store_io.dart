import '../../../core/security/wallet_secret_vault.dart';

/// 4-digit transaction PIN used for withdrawals (separate from wallet unlock passcode).
///
/// Only a salted hash is stored, inside platform secure storage.
class WalletTransactionPinStore {
  WalletTransactionPinStore._();

  static final WalletTransactionPinStore instance =
      WalletTransactionPinStore._();

  final _vault = WalletSecretVault.instance;

  String? pendingPin;
  bool hasPin = false;

  Future<void> load() async {
    try {
      await _vault.migrateLegacyPlaintextSecrets();
      hasPin = await _vault.hasSecret(WalletSecretVault.transactionPinKey);
    } on Object {
      hasPin = false;
    }
  }

  void setPendingPin(String code) {
    pendingPin = code;
  }

  Future<void> savePin(String code) async {
    await _vault.saveSecret(
      key: WalletSecretVault.transactionPinKey,
      plaintext: code,
    );
    pendingPin = null;
    hasPin = true;
  }

  Future<bool> verifyPin(String code) {
    return _vault.verifySecret(
      key: WalletSecretVault.transactionPinKey,
      plaintext: code,
    );
  }

  Future<void> clear() async {
    pendingPin = null;
    hasPin = false;
    await _vault.deleteSecret(WalletSecretVault.transactionPinKey);
  }
}
