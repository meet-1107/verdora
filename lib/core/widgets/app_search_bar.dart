import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Verdora search bar: rounded (radius 16), leading search icon, grey
/// placeholder, optional trailing filter button. Height ~48.
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    this.controller,
    this.hint = 'Search…',
    this.onChanged,
    this.onFilterTap,
    this.onTap,
    this.readOnly = false,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterTap;

  /// When set, tapping the bar fires this instead of focusing. Pair with
  /// [readOnly] to use the bar as a navigation entry (e.g. open a search page).
  final VoidCallback? onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              readOnly: readOnly,
              onTap: onTap,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                prefixIcon: const Icon(Icons.search),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.search),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        if (onFilterTap != null) ...[
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            width: 48,
            child: Material(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.search),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.search),
                onTap: onFilterTap,
                child: Icon(Icons.tune, color: scheme.onPrimaryContainer),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
