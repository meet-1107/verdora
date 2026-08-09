import 'package:flutter/material.dart';

/// Time-aware greeting + name, for dashboard headers/app bars.
class AppGreeting extends StatelessWidget {
  const AppGreeting({
    super.key,
    required this.name,
    this.compact = false,
  });

  final String name;

  /// When true, renders a small stacked variant suited to an AppBar title.
  final bool compact;

  static String greetingFor(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = greetingFor(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          greeting,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: compact
              ? theme.textTheme.titleLarge
              : theme.textTheme.headlineMedium,
        ),
      ],
    );
  }
}
