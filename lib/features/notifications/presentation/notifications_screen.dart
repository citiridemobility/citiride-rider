import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/citiride_empty_state.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';
import '../data/citiride_notifications_repository.dart';

class NotificationsPeekOverlay extends StatelessWidget {
  const NotificationsPeekOverlay({
    super.key,
    required this.onClose,
    required this.onViewAll,
  });

  final VoidCallback onClose;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final activities = CitirideNotificationsRepository()
        .watchCurrentRiderActivities();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('notifications-peek-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.46)),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: topInset + 70,
          child: Material(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 32,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            key: const ValueKey('notifications-peek-close'),
                            onPressed: onClose,
                            icon: const Icon(Icons.close, color: AppColors.white),
                            iconSize: 25,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 36,
                              height: 36,
                            ),
                            tooltip: 'Close notifications',
                          ),
                        ),
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  StreamBuilder<List<CitirideNotification>>(
                    stream: activities,
                    builder: (context, snapshot) {
                      final notifications = snapshot.data ?? const [];
                      if (notifications.isEmpty) {
                        return const CitirideEmptyState(
                          compact: true,
                          icon: Icons.notifications_none_rounded,
                          title: 'No notifications yet',
                          subtitle:
                              'Ride updates and wallet transactions will show up here.',
                        );
                      }

                      return Column(
                        children: [
                          for (var index = 0;
                              index < 3 && index < notifications.length;
                              index++) ...[
                            _NotificationRow(
                              notification: notifications[index],
                              onTap: () => _openNotificationDetails(
                                context,
                                notifications[index],
                              ),
                            ),
                            if (index < 2 && index < notifications.length - 1)
                              const SizedBox(height: 18),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    key: const ValueKey('notifications-peek-view-all'),
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.white,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(72, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'View all',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NotificationsViewAllScreen extends StatelessWidget {
  const NotificationsViewAllScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 44,
              child: Opacity(
                opacity: 0.26,
                child: CompatibleSvgPicture.asset(
                  'assets/images/Basemap image.svg',
                  fit: BoxFit.cover,
                  semanticsLabel: 'Notifications map background',
                ),
              ),
            ),
            Positioned.fill(
              top: 44,
              child: ColoredBox(
                color: const Color(0xFF242424),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _NotificationsHeader(
                          onBack: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/home');
                            }
                          },
                        ),
                        const SizedBox(height: 28),
                        Expanded(
                          child: StreamBuilder<List<CitirideNotification>>(
                            stream: CitirideNotificationsRepository()
                                .watchCurrentRiderActivities(),
                            builder: (context, snapshot) {
                              final notifications = snapshot.data ?? const [];
                              if (notifications.isEmpty) {
                                return const CitirideEmptyState(
                                  icon: Icons.notifications_none_rounded,
                                  title: 'No notifications yet',
                                  subtitle:
                                      'Ride updates and wallet transactions will show up here.',
                                );
                              }
                              return ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: notifications.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) =>
                                    _NotificationRow(
                                  notification: notifications[index],
                                  onTap: () => _openNotificationDetails(
                                    context,
                                    notifications[index],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openNotificationDetails(
  BuildContext context,
  CitirideNotification notification,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NotificationDetailScreen(notification: notification),
    ),
  );
}

class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({super.key, required this.notification});

  final CitirideNotification notification;

  @override
  Widget build(BuildContext context) {
    final isWallet = notification.kind == CitirideNotificationKind.wallet;
    return Scaffold(
      backgroundColor: AppColors.citirideBlack,
      appBar: AppBar(
        backgroundColor: AppColors.citirideBlack,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text('Notification details'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.white.withValues(alpha: 0.08)),
            ),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isWallet
                        ? Icons.account_balance_wallet_rounded
                        : Icons.local_taxi_rounded,
                    color: AppColors.citirideYellow,
                    size: 28,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    notification.title,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fullDateTime(notification.occurredAt),
                    style: const TextStyle(color: Color(0xFFABABAB), fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    notification.details,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
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
          const Text(
            'Notifications',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final CitirideNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isWallet = notification.kind == CitirideNotificationKind.wallet;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.citirideYellow.withValues(alpha: 0.13),
                ),
                child: Icon(
                  isWallet
                      ? Icons.account_balance_wallet_rounded
                      : Icons.local_taxi_rounded,
                  color: AppColors.citirideYellow,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB0B0B0),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _timeAgo(notification.occurredAt),
                style: const TextStyle(
                  color: Color(0xFFCECECE),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _timeAgo(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${value.day}/${value.month}/${value.year}';
}

String _fullDateTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '${value.day}/${value.month}/${value.year} at $hour:$minute $period';
}
