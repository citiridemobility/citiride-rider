class WalletEnrollmentStore {
  WalletEnrollmentStore._();

  static final WalletEnrollmentStore instance = WalletEnrollmentStore._();

  bool isEnrolled = false;
  String? passcode;
  String? pendingPasscode;

  Future<void> load() async {}

  Future<void> setPendingPasscode(String code) async {
    pendingPasscode = code;
  }

  Future<void> completeEnrollment(String code) async {
    passcode = code;
    pendingPasscode = null;
    isEnrolled = true;
  }

  bool verifyPasscode(String code) {
    return passcode != null && passcode == code;
  }

  Future<void> markEnrolled() async {
    isEnrolled = true;
  }

  Future<void> clear() async {
    isEnrolled = false;
    passcode = null;
    pendingPasscode = null;
  }
}
