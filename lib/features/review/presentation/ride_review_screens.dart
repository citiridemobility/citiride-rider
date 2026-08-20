import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

class RideSuccessScreen extends StatefulWidget {
  const RideSuccessScreen({
    super.key,
    this.rideType = 'regular',
    this.paymentMethod = 'cash',
  });

  final String rideType;
  final String paymentMethod;

  @override
  State<RideSuccessScreen> createState() => _RideSuccessScreenState();
}

class _RideSuccessScreenState extends State<RideSuccessScreen> {
  static const _suggestedComments = [
    'Safe driving',
    'Great service',
    'Punctual',
    'Good car quality',
    'Respectful',
  ];

  static const _tipOptions = <int>[0, 200, 500, 1000];

  int _rating = 0;
  String? _selectedComment;
  int? _selectedTip;

  bool get _canSubmit => _rating > 0 && _selectedComment != null;

  String get _price => widget.rideType == 'vip' ? '\u20A67500' : '\u20A63500';

  String get _paymentLabel {
    return widget.paymentMethod == 'wallet' ? 'CitiRide Wallet' : 'Cash';
  }

  String get _paymentIcon {
    return widget.paymentMethod == 'wallet'
        ? 'assets/images/wallet icon.svg'
        : 'assets/images/cash icon.svg';
  }

  String get _ratingText {
    return switch (_rating) {
      5 => 'Excellent!',
      4 => 'Great!',
      3 => 'Good',
      2 => 'Fair',
      1 => 'Poor',
      _ => '',
    };
  }

  void _selectComment(String comment) {
    setState(() {
      _selectedComment = comment;
    });
  }

  void _openReview() {
    final reviewUri = Uri(
      path: '/review',
      queryParameters: {
        'ride': widget.rideType,
        'payment': widget.paymentMethod,
      },
    );
    context.push(reviewUri.toString());
  }

  void _submitReview() {
    if (!_canSubmit) {
      return;
    }

    context.go('/review-submitted');
  }

  void _close() {
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return _DarkReviewScaffold(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth > 430
                ? 430.0
                : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Stack(
                  children: [
                    Positioned(
                      left: 10,
                      top: 20,
                      child: IconButton(
                        key: const ValueKey('ride-success-close-button'),
                        onPressed: _close,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 42,
                          height: 42,
                        ),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 22,
                      right: 22,
                      top: 108,
                      child: _RidePaymentSummary(
                        iconAsset: _paymentIcon,
                        label: _paymentLabel,
                        price: _price,
                      ),
                    ),
                    Positioned.fill(
                      top: constraints.maxHeight * 0.35,
                      bottom: 128 + MediaQuery.paddingOf(context).bottom,
                      child: Column(
                        children: [
                          const Text(
                            'How was your ride?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _RideRatingSelector(
                            rating: _rating,
                            onChanged: (rating) {
                              setState(() {
                                _rating = rating;
                              });
                            },
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: _ratingText.isEmpty
                                ? const SizedBox(height: 28)
                                : Padding(
                                    key: ValueKey(_ratingText),
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      _ratingText,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF8F8F8F),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        height: 1,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                          ),
                          const Spacer(),
                          _TipOptionsRow(
                            options: _tipOptions,
                            selectedTip: _selectedTip,
                            onSelected: (tip) {
                              setState(() => _selectedTip = tip);
                            },
                          ),
                          const SizedBox(height: 16),
                          _SuggestedCommentPills(
                            comments: _suggestedComments,
                            selectedComment: _selectedComment,
                            onSelected: _selectComment,
                            onAdditionalComment: _openReview,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 22,
                      right: 22,
                      bottom: MediaQuery.paddingOf(context).bottom + 48,
                      child: _ReviewPrimaryButton(
                        key: const ValueKey('ride-success-done-button'),
                        label: 'Done',
                        isEnabled: _canSubmit,
                        onPressed: _submitReview,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    this.rideType = 'regular',
    this.paymentMethod = 'cash',
  });

  final String rideType;
  final String paymentMethod;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final TextEditingController _reviewController;

  bool get _canContinue => _reviewController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _reviewController = TextEditingController();
    _reviewController.addListener(_handleReviewChanged);
  }

  @override
  void dispose() {
    _reviewController.removeListener(_handleReviewChanged);
    _reviewController.dispose();
    super.dispose();
  }

  void _handleReviewChanged() {
    setState(() {});
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    final rideSuccessUri = Uri(
      path: '/ride-success',
      queryParameters: {
        'ride': widget.rideType,
        'payment': widget.paymentMethod,
      },
    );
    context.go(rideSuccessUri.toString());
  }

  void _submitReview() {
    if (!_canContinue) {
      return;
    }

    context.go('/review-submitted');
  }

  @override
  Widget build(BuildContext context) {
    return _DarkReviewScaffold(
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth > 430
                ? 430.0
                : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Stack(
                  children: [
                    Positioned(
                      left: 14,
                      top: 20,
                      child: IconButton(
                        key: const ValueKey('review-back-button'),
                        onPressed: _goBack,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 42,
                          height: 42,
                        ),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppColors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 64,
                      right: 64,
                      top: 30,
                      child: Text(
                        'Review',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 23,
                      right: 23,
                      top: 110,
                      child: _ReviewTextField(controller: _reviewController),
                    ),
                    Positioned(
                      left: 22,
                      right: 22,
                      bottom: MediaQuery.paddingOf(context).bottom + 48,
                      child: _ReviewPrimaryButton(
                        key: const ValueKey('manual-review-continue-button'),
                        label: 'Continue',
                        isEnabled: _canContinue,
                        onPressed: _submitReview,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ReviewSubmittedScreen extends StatefulWidget {
  const ReviewSubmittedScreen({super.key});

  @override
  State<ReviewSubmittedScreen> createState() => _ReviewSubmittedScreenState();
}

class _ReviewSubmittedScreenState extends State<ReviewSubmittedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DarkReviewScaffold(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth > 430
                ? 430.0
                : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FadeTransition(
                            opacity: _opacity,
                            child: ScaleTransition(
                              scale: _scale,
                              child: const CompatibleSvgPicture.asset(
                                'assets/images/review icon.svg',
                                width: 166,
                                height: 166,
                                fit: BoxFit.contain,
                                semanticsLabel: 'Review submitted checkmark',
                              ),
                            ),
                          ),
                          const SizedBox(height: 38),
                          const Text(
                            'Review successfully submitted',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: MediaQuery.paddingOf(context).bottom + 56,
                      child: SizedBox(
                        height: 49,
                        child: FilledButton(
                          key: const ValueKey('review-back-home-button'),
                          onPressed: () => context.go('/home'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.citirideYellow,
                            foregroundColor: AppColors.citirideBlack,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: 0,
                            ),
                          ),
                          child: const Text('Back To Home'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DarkReviewScaffold extends StatelessWidget {
  const _DarkReviewScaffold({
    required this.child,
    this.resizeToAvoidBottomInset = false,
  });

  final Widget child;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.citirideBlack,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppColors.citirideBlack,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        backgroundColor: AppColors.citirideBlack,
        body: child,
      ),
    );
  }
}

class _RidePaymentSummary extends StatelessWidget {
  const _RidePaymentSummary({
    required this.iconAsset,
    required this.label,
    required this.price,
  });

  final String iconAsset;
  final String label;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            CompatibleSvgPicture.asset(
              iconAsset,
              width: 21,
              height: 21,
              fit: BoxFit.contain,
              semanticsLabel: '$label payment icon',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              price,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RideRatingSelector extends StatelessWidget {
  const _RideRatingSelector({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ride rating',
      value: rating == 0 ? 'No rating selected' : '$rating stars',
      child: SizedBox(
        width: 132,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const CompatibleSvgPicture.asset(
              'assets/images/rating.svg',
              width: 132,
              height: 20,
              fit: BoxFit.contain,
              semanticsLabel: 'Rating stars',
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var index = 0; index < 5; index++)
                  GestureDetector(
                    key: ValueKey('ride-rating-star-${index + 1}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(index + 1),
                    child: SizedBox(
                      width: 24,
                      height: 28,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: rating > index ? 1 : 0,
                          child: const Icon(
                            Icons.star_rounded,
                            color: AppColors.citirideYellow,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TipOptionsRow extends StatelessWidget {
  const _TipOptionsRow({
    required this.options,
    required this.selectedTip,
    required this.onSelected,
  });

  final List<int> options;
  final int? selectedTip;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Text(
            'Add a tip for your driver?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8F8F8F),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final tip in options)
                _TipChip(
                  label: tip == 0 ? 'No tip' : '\u20A6$tip',
                  isSelected: selectedTip == tip,
                  onTap: () => onSelected(tip),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.citirideYellow : const Color(0xFF242424),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.citirideYellow
                : const Color(0xFF3A3A3A),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.citirideBlack : AppColors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _SuggestedCommentPills extends StatelessWidget {
  const _SuggestedCommentPills({
    required this.comments,
    required this.selectedComment,
    required this.onSelected,
    required this.onAdditionalComment,
  });

  final List<String> comments;
  final String? selectedComment;
  final ValueChanged<String> onSelected;
  final VoidCallback onAdditionalComment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 42),
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final comment in comments)
            _ReviewPill(
              label: comment,
              isSelected: selectedComment == comment,
              onTap: () => onSelected(comment),
            ),
          _ReviewPill(
            label: 'Any additional comment?',
            leadingIcon: Icons.add,
            isSelected: false,
            onTap: onAdditionalComment,
          ),
        ],
      ),
    );
  }
}

class _ReviewPill extends StatelessWidget {
  const _ReviewPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.leadingIcon,
  });

  final String label;
  final IconData? leadingIcon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected
        ? AppColors.citirideBlack
        : const Color(0xFF8F8F8F);

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        key: ValueKey('review-pill-$label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.white : const Color(0xFF8F8F8F),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, color: foreground, size: 14),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1,
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

class _ReviewTextField extends StatelessWidget {
  const _ReviewTextField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('manual-review-field'),
      controller: controller,
      minLines: 1,
      maxLines: 5,
      cursorColor: AppColors.citirideYellow,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.2,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        hintText: 'Write your review',
        hintStyle: const TextStyle(
          color: Color(0xFF8F8F8F),
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.2,
          letterSpacing: 0,
        ),
        filled: true,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.white, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.white, width: 1.2),
        ),
      ),
    );
  }
}

class _ReviewPrimaryButton extends StatelessWidget {
  const _ReviewPrimaryButton({
    super.key,
    required this.label,
    required this.isEnabled,
    required this.onPressed,
  });

  final String label;
  final bool isEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 49,
      child: FilledButton(
        onPressed: isEnabled ? onPressed : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const Color(0xFF9C9C9C);
            }
            return AppColors.citirideYellow;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const Color(0xFF333333);
            }
            return AppColors.citirideBlack;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
