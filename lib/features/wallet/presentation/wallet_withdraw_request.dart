import 'wallet_banks.dart';

class WalletWithdrawRequest {
  const WalletWithdrawRequest({
    required this.bank,
    required this.accountNumber,
    required this.amount,
    this.accountName = '',
  });

  final WalletBank bank;
  final String accountNumber;
  final int amount;
  final String accountName;
}
