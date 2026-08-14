import 'package:flutter/material.dart';

import '../../../../shared/widgets/compatible_svg_picture.dart';

class AuthNumberPad extends StatelessWidget {
  const AuthNumberPad({
    super.key,
    required this.keyDiameter,
    required this.keyGap,
    required this.onDigitPressed,
    required this.onBackspacePressed,
  });

  final double keyDiameter;
  final double keyGap;
  final ValueChanged<String> onDigitPressed;
  final VoidCallback onBackspacePressed;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'backspace'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final value in row)
                SizedBox.square(
                  dimension: keyDiameter,
                  child: value.isEmpty
                      ? const SizedBox.shrink()
                      : _DialKey(
                          value: value,
                          onPressed: value == 'backspace'
                              ? onBackspacePressed
                              : () => onDigitPressed(value),
                        ),
                ),
            ],
          ),
          if (row != rows.last) SizedBox(height: keyGap),
        ],
      ],
    );
  }
}

class _DialKey extends StatelessWidget {
  const _DialKey({required this.value, required this.onPressed});

  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isBackspace = value == 'backspace';

    return Semantics(
      button: true,
      label: isBackspace ? 'Delete digit' : 'Number $value',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          key: ValueKey('dial-key-$value'),
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE4E4EA), width: 1),
            ),
            child: Center(
              child: isBackspace
                  ? const CompatibleSvgPicture.asset(
                      'assets/images/cancel button.svg',
                      key: ValueKey('keypad-cancel-icon'),
                      width: 36,
                      height: 24,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF9D9D9D),
                        fontSize: 39,
                        fontWeight: FontWeight.w400,
                        height: 1,
                        letterSpacing: 0,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
