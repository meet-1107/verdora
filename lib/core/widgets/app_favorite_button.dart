import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Animated heart toggle. Dumb widget: pass [isFavorite] and [onTap].
class AppFavoriteButton extends StatelessWidget {
  const AppFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onTap,
  });

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          key: ValueKey<bool>(isFavorite),
          color: isFavorite
              ? AppColors.error
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
