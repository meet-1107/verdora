import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Verdora card: white, soft shadow, 20 radius (from theme), default 20 padding.
/// Optional [onTap] makes the whole card tappable with an ink ripple.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}
