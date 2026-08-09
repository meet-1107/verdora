import 'package:flutter/material.dart';

/// A simple breadcrumb trail: Home > Category > Subcategory. Last item is
/// emphasised. Non-interactive by default (orientation aid).
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final isLast = i == items.length - 1;
      children.add(Flexible(
        child: Text(
          items[i],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isLast ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ));
      if (!isLast) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.chevron_right,
              size: 14, color: scheme.onSurfaceVariant),
        ));
      }
    }
    return Row(children: children);
  }
}
