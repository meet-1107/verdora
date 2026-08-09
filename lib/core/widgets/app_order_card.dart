import 'package:flutter/material.dart';

import 'app_status_chip.dart';

/// A single order row: title (invoice/order no.), a subtitle line, a status
/// chip and a chevron. Dumb widget — pass display strings + status values so it
/// carries no feature dependencies.
class AppOrderCard extends StatelessWidget {
  const AppOrderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusValue,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String statusLabel;
  final String statusValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStatusChip(label: statusLabel, statusValue: statusValue),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
