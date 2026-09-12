import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/auth/citiride_wallet_client.dart';
import '../../../core/location/citiride_fare.dart';
import '../../../shared/widgets/citiride_slide_button.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../data/ride_repository.dart';
import '../domain/live_ride.dart';

class RidePaymentScreen extends StatefulWidget {
  const RidePaymentScreen({
    super.key,
    this.rideType = 'regular',
    this.paymentMethod = 'cash',
    this.estimatedFare,
    this.rideId,
  });

  final String rideType;
  final String paymentMethod;
  final double? estimatedFare;
  final String? rideId;

  @override
  State<RidePaymentScreen> createState() => _RidePaymentScreenState();
}

class _RidePaymentScreenState extends State<RidePaymentScreen> {
  final _walletClient = CitirideWalletClient();

  StreamSubscription<LiveRide>? _rideSub;
  LiveRide? _ride;
  double _walletBalance = 0;
  bool _loadingWallet = true;
  bool _walletReady = false;
  bool _paying = false;
  bool _didNavigate = false;
  String? _error;

  String get _rideId => widget.rideId?.trim() ?? '';

  bool get _isCash =>
      (_ride?.paymentMethod ?? widget.paymentMethod).toLowerCase() == 'cash';

  double get _fareAmount {
    final ride = _ride;
    if (ride != null) {
      return ride.fare.finalFare ?? ride.fare.estimated;
    }
    return widget.estimatedFare ??
        CitirideFareCalculator.fallback(
          CitirideFareRates.tierFromRideType(widget.rideType),
        ).estimatedTotal;
  }

  String get _driverName {
    final name = _ride?.driverName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return 'your driver';
  }

  bool get _canAct =>
      !_paying && _rideId.isNotEmpty && !(_ride?.isPaid ?? false);

  bool get _canPay => _canAct && !_loadingWallet;

  @override
  void initState() {
    super.initState();
    _watchRide();
    unawaited(_loadWallet());
  }

  @override
  void dispose() {
    unawaited(_rideSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  void _watchRide() {
    if (_rideId.isEmpty) {
      return;
    }
    try {
      _rideSub = RideRepository().watchRide(_rideId).listen(
        (ride) {
          if (!mounted) {
            return;
          }
          setState(() => _ride = ride);
          if (ride.isPaid || ride.status == RideStatus.completed) {
            _goToReview();
          }
        },
        onError: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _error ??= 'Unable to load this trip.';
          });
        },
      );
    } on Object {
      // Firebase may be unavailable in widget tests.
    }
  }

  Future<void> _loadWallet() async {
    setState(() {
      _loadingWallet = true;
    });
    try {
      final wallet = await _walletClient.fetchWallet();
      if (!mounted) {
        return;
      }
      setState(() {
        _walletBalance = wallet.availableBalance;
        _loadingWallet = false;
        _walletReady = true;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingWallet = false;
        _walletReady = false;
        _error = error is CitirideWalletException
            ? error.message
            : 'Unable to load your wallet.';
      });
    }
  }

  Uri _reviewUri() {
    return Uri(
      path: '/ride-success',
      queryParameters: {
        'ride': widget.rideType,
        'payment': widget.paymentMethod,
        if (widget.estimatedFare != null)
          'fare': widget.estimatedFare!.round().toString(),
        if (_rideId.isNotEmpty) 'rideId': _rideId,
      },
    );
  }

  void _goToReview() {
    if (!mounted || _didNavigate) {
      return;
    }
    _didNavigate = true;
    context.go(_reviewUri().toString());
  }

  Future<void> _openAddMoney() async {
    await context.push('/wallet-add-money');
    if (mounted) {
      unawaited(_loadWallet());
    }
  }

  Future<void> _payFromWallet() async {
    if (!_canPay) {
      return;
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      await _walletClient.payRide(rideId: _rideId);
      if (!mounted) {
        return;
      }
      _goToReview();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paying = false;
        _error = error is CitirideWalletException
            ? error.message
            : 'Unable to pay for this ride.';
      });
    }
  }

  Future<void> _confirmCash() async {
    if (!_canAct) {
      return;
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      await _walletClient.confirmCashRide(rideId: _rideId);
      if (!mounted) {
        return;
      }
      _goToReview();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paying = false;
        _error = error is CitirideWalletException
            ? error.message
            : 'Unable to confirm cash payment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fareLabel = formatNaira(_fareAmount);
    final balanceLabel = formatNaira(_walletBalance);
    final insufficient = _walletReady && _walletBalance < _fareAmount;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.citirideBlack,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.citirideBlack,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Confirm payment',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  fareLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Pay $_driverName from your CitiRide wallet',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8F8F8F),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CompatibleSvgPicture.asset(
                            'assets/images/wallet icon.svg',
                            width: 22,
                            height: 22,
                            semanticsLabel: 'Wallet',
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Wallet balance',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            _loadingWallet ? '…' : balanceLabel,
                            style: const TextStyle(
                              color: AppColors.citirideYellow,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Trip fare',
                              style: TextStyle(
                                color: Color(0xFF8F8F8F),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            fareLabel,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (insufficient) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openAddMoney,
                    child: const Text(
                      'Add money',
                      style: TextStyle(
                        color: AppColors.citirideYellow,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                CitirideSlideButton(
                  key: const ValueKey('ride-payment-pay-button'),
                  label: _paying ? 'Paying…' : 'Pay $fareLabel',
                  onConfirm: _payFromWallet,
                  enabled: _canPay && !insufficient,
                ),
                if (_isCash) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('ride-payment-cash-button'),
                    onPressed: _canAct ? _confirmCash : null,
                    child: const Text(
                      'I’ve paid in cash',
                      style: TextStyle(
                        color: Color(0xFF8F8F8F),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
