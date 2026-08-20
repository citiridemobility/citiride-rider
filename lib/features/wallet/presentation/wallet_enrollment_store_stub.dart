import '../../../core/security/wallet_secret_vault.dart';

class WalletEnrollmentStore {
  WalletEnrollmentStore._();

  static final WalletEnrollmentStore instance = WalletEnrollmentStore._();

  final _vault = WalletSecretVault.instance;

  bool isEnrolled = false;
  String? pendingPasscode;

  Future<void> load() async {
    isEnrolled = await _vault.hasSecret(WalletSecretVault.passcodeKey);
  }

  Future<void> setPendingPasscode(String code) async {
    pendingPasscode = code;
  }

  Future<void> completeEnrollment(String code) async {
    await _vault.saveSecret(
      key: WalletSecretVault.passcodeKey,
      plaintext: code,
    );
    pendingPasscode = null;
    isEnrolled = true;
  }

  Future<bool> verifyPasscode(String code) {
    return _vault.verifySecret(
      key: WalletSecretVault.passcodeKey,
      plaintext: code,
    );
  }

  Future<void> markEnrolled() async {
    isEnrolled = true;
  }

  Future<void> clear() async {
    isEnrolled = false;
    pendingPasscode = null;
    await _vault.deleteSecret(WalletSecretVault.passcodeKey);
  }
}
