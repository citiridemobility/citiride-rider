import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

export 'wallet_enrollment_store.dart';

Future<void> showWalletTimedLoadingDialog(
  BuildContext context, {
  required String message,
  Duration delay = const Duration(seconds: 2),
}) async {
  var dialogVisible = true;
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (dialogContext) {
        return WalletLoadingDialog(message: message);
      },
    ).whenComplete(() {
      dialogVisible = false;
    }),
  );

  await Future<void>.delayed(delay);
  if (!context.mounted || !dialogVisible) {
    return;
  }

  dialogVisible = false;
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
}

class WalletLoadingDialog extends StatelessWidget {
  const WalletLoadingDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: message,
        child: Container(
          width: 156,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.citirideBlack,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  color: AppColors.citirideYellow,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletFlowTopBar extends StatelessWidget {
  const WalletFlowTopBar({
    super.key,
    required this.onBack,
    this.onNeedHelp,
  });

  final VoidCallback onBack;
  final VoidCallback? onNeedHelp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          iconSize: 24,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          tooltip: 'Back',
        ),
        const Spacer(),
        TextButton(
          onPressed: onNeedHelp ?? () {},
          style: TextButton.styleFrom(
            foregroundColor: AppColors.citirideYellow,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Need Help?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class WalletProgressBar extends StatelessWidget {
  const WalletProgressBar({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 4,
        backgroundColor: const Color(0xFF2A2A2A),
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.citirideYellow),
      ),
    );
  }
}

class WalletPrimaryButton extends StatelessWidget {
  const WalletPrimaryButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.citirideYellow,
          foregroundColor: AppColors.citirideBlack,
          disabledBackgroundColor: const Color(0xFF918900),
          disabledForegroundColor: const Color(0xFF514D00),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
