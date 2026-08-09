import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Preset quantity buttons (100 / 250 / 500 …) for fast bulk entry.
class AppQuickQuantityButtons extends StatelessWidget {
  const AppQuickQuantityButtons({
    super.key,
    required this.onSelected,
    this.presets = const [100, 250, 500, 1000, 2000],
  });

  final ValueChanged<int> onSelected;
  final List<int> presets;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final p in presets)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            ),
            onPressed: () => onSelected(p),
            child: Text('$p'),
          ),
      ],
    );
  }
}
