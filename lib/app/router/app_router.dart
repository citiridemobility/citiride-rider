import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/citiride_auth_service.dart';
import '../../core/location/route_query.dart';
import '../../features/auth/presentation/enter_code_screen.dart';
import '../../features/auth/presentation/enter_number_screen.dart';
import '../../features/driver/presentation/cancel_ride_reason_screen.dart';
import '../../features/driver/presentation/looking_for_driver_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/location/presentation/set_location_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/payment/presentation/payment_options_screen.dart';
import '../../features/pickup/presentation/select_pickup_location_screen.dart';
import '../../features/profile/presentation/personal_info_screen.dart';
import '../../features/review/presentation/ride_review_screens.dart';
import '../../features/rides/domain/ride_history.dart';
import '../../features/rides/presentation/ride_details_screen.dart';
import '../../features/rides/presentation/rides_screen.dart';
import '../../features/route/presentation/route_selection_screen.dart';
import '../../features/ride/presentation/select_ride_screen.dart';
import '../../features/settings/presentation/settings_screens.dart';

import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/wallet/presentation/wallet_add_money_screen.dart';
import '../../features/wallet/presentation/wallet_banks.dart';
import '../../features/wallet/presentation/wallet_email_screen.dart';
import '../../features/wallet/presentation/wallet_get_started_screen.dart';
import '../../features/wallet/presentation/wallet_home_screen.dart';
import '../../features/wallet/presentation/wallet_passcode_screen.dart';
import '../../features/wallet/presentation/wallet_phone_number_screen.dart';
import '../../features/wallet/presentation/wallet_sign_up_screen.dart';
import '../../features/wallet/presentation/wallet_terms_screen.dart';
import '../../features/wallet/presentation/wallet_verify_email_screen.dart';
import '../../features/wallet/presentation/wallet_verify_phone_screen.dart';
import '../../features/wallet/presentation/wallet_transaction_pin_screens.dart';
import '../../features/wallet/presentation/wallet_withdraw_auth_screens.dart';
import '../../features/wallet/presentation/wallet_withdraw_pin_screen.dart';
import '../../features/wallet/presentation/wallet_withdraw_request.dart';
import '../../features/wallet/presentation/wallet_withdraw_screen.dart';
import '../../features/wallet/presentation/wallet_withdrawal_success_screen.dart';
import '../../features/welcome/presentation/welcome_screen.dart';

abstract final class AppRouter {
  static Page<void> _noTransitionPage(GoRouterState state, Widget child) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  static GoRouter create() {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          name: 'splash',
          builder: (context, state) {
            return const SplashScreen();
          },
        ),
        GoRoute(
          path: '/onboarding',
          name: 'onboarding',
          pageBuilder: (context, state) {
            return _noTransitionPage(state, const OnboardingScreen());
          },
        ),
        GoRoute(
          path: '/welcome',
          name: 'welcome',
          builder: (context, state) {
            return const WelcomeScreen();
          },
        ),
        GoRoute(
          path: '/enter-number',
          name: 'enter-number',
          builder: (context, state) {
            return const EnterNumberScreen();
          },
        ),
        GoRoute(
          path: '/enter-code',
          name: 'enter-code',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            final resendTokenValue = query['resendToken'];

            return EnterCodeScreen(
              phoneDigits: query['phone'] ?? '',
              phoneNumber: query['phoneE164'],
              email: query['email'],
              authMethod: CitirideAuthMethod.values.firstWhere(
                (method) => method.name == query['authMethod'],
                orElse: () => CitirideAuthMethod.phone,
              ),
              verificationId: query['verificationId'],
              resendToken: resendTokenValue == null
                  ? null
                  : int.tryParse(resendTokenValue),
              verificationMode: CitiridePhoneVerificationMode.values.firstWhere(
                (mode) => mode.name == query['mode'],
                orElse: () => CitiridePhoneVerificationMode.demo,
              ),
            );
          },
        ),
        GoRoute(
          path: '/set-location',
          name: 'set-location',
          builder: (context, state) {
            return const SetLocationScreen();
          },
        ),
        GoRoute(
          path: '/personal-info',
          name: 'personal-info',
          builder: (context, state) {
            return const PersonalInfoScreen();
          },
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) {
            return const SettingsScreen();
          },
        ),
        GoRoute(
          path: '/security',
          name: 'security',
          builder: (context, state) {
            return const SecurityScreen();
          },
        ),
        GoRoute(
          path: '/change-passcode',
          name: 'change-passcode',
          builder: (context, state) {
            return const ChangePasscodeScreen();
          },
        ),
        GoRoute(
          path: '/reset-pin-otp',
          name: 'reset-pin-otp',
          builder: (context, state) {
            return const ResetPinOtpScreen();
          },
        ),
        GoRoute(
          path: '/reset-pin-new',
          name: 'reset-pin-new',
          builder: (context, state) {
            return const ResetPinNewPinScreen();
          },
        ),
        GoRoute(
          path: '/home',
          name: 'home',
          pageBuilder: (context, state) {
            return _noTransitionPage(
              state,
              HomeScreen(
                initialLocationLabel: state.uri.queryParameters['pickup'],
                initialLocation: latLngFromQuery(
                  state.uri.queryParameters,
                  'pickup',
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/notifications',
          name: 'notifications',
          builder: (context, state) {
            return const NotificationsViewAllScreen();
          },
        ),
        GoRoute(
          path: '/rides',
          name: 'rides',
          pageBuilder: (context, state) {
            return _noTransitionPage(
              state,
              RidesScreen(
                initialTab: state.uri.queryParameters['tab'] ?? 'upcoming',
              ),
            );
          },
        ),
        GoRoute(
          path: '/wallet-sign-up',
          name: 'wallet-sign-up',
          pageBuilder: (context, state) {
            return _noTransitionPage(state, const WalletSignUpScreen());
          },
        ),
        GoRoute(
          path: '/wallet-get-started',
          name: 'wallet-get-started',
          builder: (context, state) {
            return const WalletGetStartedScreen();
          },
        ),
        GoRoute(
          path: '/wallet-phone-number',
          name: 'wallet-phone-number',
          builder: (context, state) {
            return const WalletPhoneNumberScreen();
          },
        ),
        GoRoute(
          path: '/wallet-verify-phone',
          name: 'wallet-verify-phone',
          builder: (context, state) {
            return WalletVerifyPhoneScreen(
              phoneDigits: state.uri.queryParameters['phone'] ?? '',
            );
          },
        ),
        GoRoute(
          path: '/wallet-email',
          name: 'wallet-email',
          builder: (context, state) {
            return const WalletEmailScreen();
          },
        ),
        GoRoute(
          path: '/wallet-verify-email',
          name: 'wallet-verify-email',
          builder: (context, state) {
            return WalletVerifyEmailScreen(
              email: state.uri.queryParameters['email'] ?? '',
            );
          },
        ),
        GoRoute(
          path: '/wallet-terms',
          name: 'wallet-terms',
          builder: (context, state) {
            return const WalletTermsScreen();
          },
        ),
        GoRoute(
          path: '/wallet-setup-passcode',
          name: 'wallet-setup-passcode',
          builder: (context, state) {
            return const WalletPasscodeScreen(mode: WalletPasscodeMode.setup);
          },
        ),
        GoRoute(
          path: '/wallet-confirm-passcode',
          name: 'wallet-confirm-passcode',
          builder: (context, state) {
            return const WalletPasscodeScreen(mode: WalletPasscodeMode.confirm);
          },
        ),
        GoRoute(
          path: '/wallet-unlock-passcode',
          name: 'wallet-unlock-passcode',
          builder: (context, state) {
            return const WalletPasscodeScreen(mode: WalletPasscodeMode.unlock);
          },
        ),
        GoRoute(
          path: '/wallet',
          name: 'wallet',
          pageBuilder: (context, state) {
            return _noTransitionPage(state, const WalletHomeScreen());
          },
        ),
        GoRoute(
          path: '/wallet-add-money',
          name: 'wallet-add-money',
          builder: (context, state) {
            return const WalletAddMoneyScreen();
          },
        ),
        GoRoute(
          path: '/wallet-withdraw',
          name: 'wallet-withdraw',
          builder: (context, state) {
            final bank = state.extra is WalletBank
                ? state.extra! as WalletBank
                : walletBanks.first;
            return WalletWithdrawScreen(initialBank: bank);
          },
        ),
        GoRoute(
          path: '/wallet-transaction-pin-setup',
          name: 'wallet-transaction-pin-setup',
          builder: (context, state) {
            final pending = state.extra is WalletWithdrawRequest
                ? state.extra! as WalletWithdrawRequest
                : null;
            return WalletTransactionPinScreen(
              mode: WalletTransactionPinMode.setup,
              pendingWithdraw: pending,
            );
          },
        ),
        GoRoute(
          path: '/wallet-transaction-pin-confirm',
          name: 'wallet-transaction-pin-confirm',
          builder: (context, state) {
            final pending = state.extra is WalletWithdrawRequest
                ? state.extra! as WalletWithdrawRequest
                : null;
            return WalletTransactionPinScreen(
              mode: WalletTransactionPinMode.confirm,
              pendingWithdraw: pending,
            );
          },
        ),
        GoRoute(
          path: '/wallet-withdraw-pin',
          name: 'wallet-withdraw-pin',
          builder: (context, state) {
            final request = state.extra is WalletWithdrawRequest
                ? state.extra! as WalletWithdrawRequest
                : WalletWithdrawRequest(
                    bank: walletBanks.first,
                    accountNumber: '',
                    amount: 0,
                  );
            return WalletWithdrawPinScreen(request: request);
          },
        ),
        GoRoute(
          path: '/wallet-withdraw-otp',
          name: 'wallet-withdraw-otp',
          builder: (context, state) {
            final extra = state.extra;
            WalletWithdrawRequest request = WalletWithdrawRequest(
              bank: walletBanks.first,
              accountNumber: '',
              amount: 0,
            );
            var email = '';
            if (extra is Map) {
              final mappedRequest = extra['request'];
              if (mappedRequest is WalletWithdrawRequest) {
                request = mappedRequest;
              }
              email = (extra['email'] as String?)?.trim() ?? '';
            }
            return WalletWithdrawOtpScreen(request: request, email: email);
          },
        ),
        GoRoute(
          path: '/wallet-withdrawal-success',
          name: 'wallet-withdrawal-success',
          builder: (context, state) {
            return const WalletWithdrawalSuccessScreen();
          },
        ),
        GoRoute(
          path: '/ride-details',
          name: 'ride-details',
          builder: (context, state) {
            return RideDetailsScreen(
              ride: rideHistoryItemById(state.uri.queryParameters['rideId']),
            );
          },
        ),
        GoRoute(
          path: '/route',
          name: 'route',
          builder: (context, state) {
            return RouteSelectionScreen(
              initialLocation:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ?? '',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
              showStopFieldInitially:
                  state.uri.queryParameters['showStop'] == 'true',
              isEditingDestinations:
                  state.uri.queryParameters['mode'] == 'edit-destinations',
              returnRideType: state.uri.queryParameters['ride'] ?? 'regular',
              returnPayment: state.uri.queryParameters['payment'] ?? 'cash',
              returnTo: state.uri.queryParameters['returnTo'] ?? 'driver-found',
            );
          },
        ),
        GoRoute(
          path: '/select-ride',
          name: 'select-ride',
          builder: (context, state) {
            return SelectRideScreen(
              initialRide: state.uri.queryParameters['ride'] ?? 'regular',
              initialPayment: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickup:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
            );
          },
        ),
        GoRoute(
          path: '/payment-options',
          name: 'payment-options',
          builder: (context, state) {
            return PaymentOptionsScreen(
              initialRide: state.uri.queryParameters['ride'] ?? 'regular',
              initialPayment: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickup:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
            );
          },
        ),
        GoRoute(
          path: '/looking-for-driver',
          name: 'looking-for-driver',
          builder: (context, state) {
            return LookingForDriverScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
            );
          },
        ),
        GoRoute(
          path: '/driver-found',
          name: 'driver-found',
          builder: (context, state) {
            return DriverFoundScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
              showDestinationChangeNotice:
                  state.uri.queryParameters['destinationChanged'] == 'true',
            );
          },
        ),
        GoRoute(
          path: '/arriving',
          name: 'arriving',
          builder: (context, state) {
            return ArrivingScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
            );
          },
        ),
        GoRoute(
          path: '/ride-arrival',
          name: 'ride-arrival',
          builder: (context, state) {
            return RideArrivalScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
            );
          },
        ),
        GoRoute(
          path: '/driving-to-destination',
          name: 'driving-to-destination',
          builder: (context, state) {
            return DrivingToDestinationScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickupLocation:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
            );
          },
        ),
        GoRoute(
          path: '/cancel-ride-reason',
          name: 'cancel-ride-reason',
          builder: (context, state) {
            return CancelRideReasonScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
            );
          },
        ),
        GoRoute(
          path: '/ride-success',
          name: 'ride-success',
          builder: (context, state) {
            return RideSuccessScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
            );
          },
        ),
        GoRoute(
          path: '/review',
          name: 'review',
          builder: (context, state) {
            return ReviewScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
            );
          },
        ),
        GoRoute(
          path: '/review-submitted',
          name: 'review-submitted',
          builder: (context, state) {
            return const ReviewSubmittedScreen();
          },
        ),
        GoRoute(
          path: '/select-pickup',
          name: 'select-pickup',
          builder: (context, state) {
            return SelectPickupLocationScreen(
              rideType: state.uri.queryParameters['ride'] ?? 'regular',
              paymentMethod: state.uri.queryParameters['payment'] ?? 'cash',
              initialPickup:
                  state.uri.queryParameters['pickup'] ?? 'Current Location',
              initialDestination:
                  state.uri.queryParameters['destination'] ??
                  'Ring Road Bus Terminal',
              initialPickupLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'pickup',
              ),
              initialDestinationLatLng: latLngFromQuery(
                state.uri.queryParameters,
                'destination',
              ),
            );
          },
        ),
      ],
    );
  }
}
