import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// AppBar notification bell with an unread-count badge (max "99+").
/// Dumb widget: pass the [count] and an [onTap]; owners supply the count from
/// their provider so this stays feature-independent.
class AppNotificationButton extends StatelessWidget {
  const AppNotificationButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: AppColors.error,
        textColor: Colors.white,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
