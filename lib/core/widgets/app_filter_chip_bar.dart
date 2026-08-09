import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A horizontal, single-select chip bar for quick filters. Reusable across
/// screens; owners pass the labels, the selected index and a callback.
class AppFilterChipBar extends StatelessWidget {
  const AppFilterChipBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.icons,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<IconData>? icons;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          return ChoiceChip(
            label: Text(labels[i]),
            avatar: icons != null
                ? Icon(
                    icons![i],
                    size: 18,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  )
                : null,
            selected: selected,
            showCheckmark: false,
            selectedColor: Theme.of(context).colorScheme.primary,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            onSelected: (_) => onSelected(i),
          );
        },
      ),
    );
  }
}
