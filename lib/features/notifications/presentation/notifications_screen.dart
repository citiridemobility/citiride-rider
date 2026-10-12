import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/citiride_empty_state.dart';
import '../../../shared/widgets/compatible_svg_picture.dart';

class CitirideNotification {
  const CitirideNotification({
    required this.title,
    required this.location,
    required this.timeAgo,
  });

  final String title;
  final String location;
  final String timeAgo;
}

const citirideNotifications = <CitirideNotification>[];

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
                            icon: const Icon(
                              Icons.close,
                              color: AppColors.white,
                            ),
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
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (citirideNotifications.isEmpty)
                    const CitirideEmptyState(
                      compact: true,
                      icon: Icons.notifications_none_rounded,
                      title: 'No notifications yet',
                      subtitle:
                          'Trip alerts and account updates will show up here.',
                    )
                  else
                    for (var index = 0; index < 3 && index < citirideNotifications.length; index++) ...[
                      _NotificationRow(
                        notification: citirideNotifications[index],
                      ),
                      if (index < 2 && index < citirideNotifications.length - 1)
                        const SizedBox(height: 21),
                    ],
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
                        height: 1,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.white,
                        letterSpacing: 0,
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
        systemNavigationBarDividerColor: AppColors.citirideBlack,
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
                              return;
                            }

                            context.go('/home');
                          },
                        ),
                        const SizedBox(height: 35),
                        Expanded(
                          child: citirideNotifications.isEmpty
                              ? const CitirideEmptyState(
                                  icon: Icons.notifications_none_rounded,
                                  title: 'No notifications yet',
                                  subtitle:
                                      'When a ride is booked, cancelled, or completed, you will see it here.',
                                )
                              : ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: citirideNotifications.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 24),
                                  itemBuilder: (context, index) {
                                    return _NotificationRow(
                                      notification:
                                          citirideNotifications[index],
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
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification});

  final CitirideNotification notification;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  height: 1.15,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                notification.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF9B9B9B),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 1.15,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            notification.timeAgo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
