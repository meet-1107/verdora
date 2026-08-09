import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Extended "View Cart" FAB with an item-count badge. Dumb widget: pass the
/// [count] and an [onTap].
class AppCartFab extends StatelessWidget {
  const AppCartFab({
    super.key,
    required this.count,
    required this.onTap,
    this.label = 'View Cart',
  });

  final int count;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: AppColors.error,
      textColor: Colors.white,
      label: Text(count > 99 ? '99+' : '$count'),
      child: FloatingActionButton.extended(
        onPressed: onTap,
        icon: const Icon(Icons.shopping_cart_outlined),
        label: Text(label),
      ),
    );
  }
}
