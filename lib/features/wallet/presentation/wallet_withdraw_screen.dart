import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import 'wallet_banks.dart';
import 'wallet_flow_widgets.dart';
import 'wallet_select_bank_sheet.dart';
import 'wallet_transaction_pin_store.dart';
import 'wallet_withdraw_request.dart';

class WalletWithdrawScreen extends StatefulWidget {
  const WalletWithdrawScreen({
    super.key,
    required this.initialBank,
  });

  final WalletBank initialBank;

  @override
  State<WalletWithdrawScreen> createState() => _WalletWithdrawScreenState();
}

class _WalletWithdrawScreenState extends State<WalletWithdrawScreen> {
  static const _presets = <int>[2000, 5000, 10000];

  late WalletBank _selectedBank;
  final _accountController = TextEditingController();
  final _amountController = TextEditingController();
  int? _selectedPreset;
  bool _isSubmitting = false;

  bool get _canWithdraw {
    final account = _accountController.text.trim();
    final amount = _parseAmount(_amountController.text);
    return !_isSubmitting &&
        account.length >= 10 &&
        amount != null &&
        amount > 0;
  }

  @override
  void initState() {
    super.initState();
    _selectedBank = widget.initialBank;
    _accountController.addListener(_onFieldsChanged);
    _amountController.addListener(_onAmountEdited);
  }

  @override
  void dispose() {
    _accountController
      ..removeListener(_onFieldsChanged)
      ..dispose();
    _amountController
      ..removeListener(_onAmountEdited)
      ..dispose();
    super.dispose();
  }

  void _onFieldsChanged() {
    setState(() {});
  }

  void _onAmountEdited() {
    final amount = _parseAmount(_amountController.text);
    setState(() {
      _selectedPreset = _presets.contains(amount) ? amount : null;
    });
  }

  int? _parseAmount(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return null;
    }
    return int.tryParse(digits);
  }

  String _formatAmount(int amount) {
    final value = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0 && (value.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(value[i]);
    }
    return buffer.toString();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/wallet');
  }

  Future<void> _changeBank() async {
    final bank = await showWalletSelectBankSheet(context);
    if (!mounted || bank == null) {
      return;
    }
    setState(() => _selectedBank = bank);
  }

  void _selectPreset(int amount) {
    setState(() {
      _selectedPreset = amount;
      _amountController.text = amount.toString();
      _amountController.selection = TextSelection.collapsed(
        offset: _amountController.text.length,
      );
    });
  }

  Future<void> _withdraw() async {
    if (!_canWithdraw) {
      return;
    }

    final amount = _parseAmount(_amountController.text);
    if (amount == null) {
      return;
    }

    final request = WalletWithdrawRequest(
      bank: _selectedBank,
      accountNumber: _accountController.text.trim(),
      amount: amount,
    );

    if (!WalletTransactionPinStore.instance.hasPin) {
      context.push('/wallet-transaction-pin-setup', extra: request);
      return;
    }

    context.push('/wallet-withdraw-pin', extra: request);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.citirideBlack,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.citirideBlack,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppColors.citirideBlack,
      ),
      child: Scaffold(
        backgroundColor: AppColors.citirideBlack,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _WithdrawHeader(onBack: _goBack),
                const SizedBox(height: 28),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bank Name',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _BankNameField(
                          bank: _selectedBank,
                          onTap: _changeBank,
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'Account Number',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _OutlinedInputField(
                          controller: _accountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'Amount',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _OutlinedInputField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(9),
                          ],
                          prefixText: '₦',
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            for (var i = 0; i < _presets.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(
                                child: _AmountPresetChip(
                                  label: '₦${_formatAmount(_presets[i])}',
                                  selected: _selectedPreset == _presets[i],
                                  onTap: () => _selectPreset(_presets[i]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: bottomInset + 16, top: 12),
                  child: WalletPrimaryButton(
                    key: const ValueKey('wallet-withdraw-to-bank-button'),
                    label: 'Withdraw to Bank',
                    enabled: _canWithdraw,
                    onPressed: _withdraw,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WithdrawHeader extends StatelessWidget {
  const _WithdrawHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              tooltip: 'Back',
            ),
          ),
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Withdraw',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Withdraw money directly to your bank account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8F8F8F),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BankNameField extends StatelessWidget {
  const _BankNameField({
    required this.bank,
    required this.onTap,
  });

  final WalletBank bank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.white, width: 1.2),
        ),
        child: Row(
          children: [
            WalletBankLogo(bank: bank, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                bank.name,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.white,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedInputField extends StatelessWidget {
  const _OutlinedInputField({
    required this.controller,
    required this.keyboardType,
    required this.inputFormatters,
    this.prefixText,
  });

  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    const fieldFill = Color(0xFF1C1C1C);
    return SizedBox(
      height: 56,
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: fieldFill,
          ),
        ),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          keyboardAppearance: Brightness.dark,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          cursorColor: AppColors.citirideYellow,
          decoration: InputDecoration(
            filled: true,
            fillColor: fieldFill,
            hoverColor: fieldFill,
            focusColor: fieldFill,
            prefixText: prefixText,
            prefixStyle: const TextStyle(
              color: AppColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: const BorderSide(color: AppColors.white, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: const BorderSide(
                color: AppColors.citirideYellow,
                width: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountPresetChip extends StatelessWidget {
  const _AmountPresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.white, width: 1.1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.citirideYellow : const Color(0xFFB5B5B5),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
