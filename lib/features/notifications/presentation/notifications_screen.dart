import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/app_notification.dart';
import '../data/notification_repository.dart';
import 'notification_providers.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];

/// In-app notification history (used by both client and admin). Month filter in
/// the header; recipients can delete a notification with a 5-second undo. Admins
/// can also broadcast a message to all clients.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  DateTime? _month; // year+month filter; null = all
  final Set<String> _pending = {}; // ids hidden pending delete
  final Map<String, Timer> _timers = {};

  @override
  void dispose() {
    // Commit any deletes still within their undo window.
    final repo = ref.read(notificationRepositoryProvider);
    for (final entry in _timers.entries) {
      entry.value.cancel();
      repo.delete(entry.key);
    }
    _timers.clear();
    super.dispose();
  }

  void _delete(String id) {
    setState(() => _pending.add(id));
    _timers[id]?.cancel();
    _timers[id] = Timer(const Duration(seconds: 5), () {
      ref.read(notificationRepositoryProvider).delete(id);
      _timers.remove(id);
      if (mounted) setState(() => _pending.remove(id));
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Notification deleted'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Undo', onPressed: () => _undo(id)),
      ));
  }

  void _undo(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    if (mounted) setState(() => _pending.remove(id));
  }

  Future<void> _pickMonth(List<AppNotification> all) async {
    // Distinct months present, newest first.
    final months = <DateTime>[];
    final seen = <String>{};
    for (final n in all) {
      final d = n.createdAt;
      if (d == null) continue;
      final key = '${d.year}-${d.month}';
      if (seen.add(key)) months.add(DateTime(d.year, d.month));
    }
    months.sort((a, b) => b.compareTo(a));

    final chosen = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('All months'),
              trailing: _month == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(sheet, 'all'),
            ),
            for (final m in months)
              ListTile(
                title: Text('${_monthNames[m.month - 1]} ${m.year}'),
                trailing:
                    (_month?.year == m.year && _month?.month == m.month)
                        ? const Icon(Icons.check)
                        : null,
                onTap: () => Navigator.pop(sheet, m),
              ),
          ],
        ),
      ),
    );
    // null = the sheet was dismissed without choosing; leave the filter as-is.
    if (!mounted || chosen == null) return;
    setState(() => _month = chosen == 'all' ? null : chosen as DateTime);
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final isAdmin =
        ref.watch(currentUserProvider).valueOrNull?.role.isAdminSide ?? false;
    final all = notifications.valueOrNull ?? const <AppNotification>[];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Notifications'),
            if (_month != null)
              Text('${_monthNames[_month!.month - 1]} ${_month!.year}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Filter by month',
            icon: Icon(_month == null
                ? Icons.calendar_month_outlined
                : Icons.calendar_month),
            onPressed: all.isEmpty ? null : () => _pickMonth(all),
          ),
          if (_month != null)
            IconButton(
              tooltip: 'Clear filter',
              icon: const Icon(Icons.filter_alt_off_outlined),
              onPressed: () => setState(() => _month = null),
            ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => showDialog(
                  context: context, builder: (_) => const _BroadcastDialog()),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Broadcast'),
            )
          : null,
      body: notifications.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(notificationsProvider)),
        data: (data) {
          var list = data.where((n) => !_pending.contains(n.id)).toList();
          if (_month != null) {
            list = list
                .where((n) =>
                    n.createdAt != null &&
                    n.createdAt!.year == _month!.year &&
                    n.createdAt!.month == _month!.month)
                .toList();
          }
          if (list.isEmpty) {
            return EmptyView(
                message: _month != null
                    ? 'No notifications in '
                        '${_monthNames[_month!.month - 1]} ${_month!.year}.'
                    : 'No notifications yet.',
                icon: Icons.notifications_none_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final n = list[i];
              return Card(
                color: n.read
                    ? null
                    : Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: Icon(n.read
                      ? Icons.notifications_none
                      : Icons.notifications_active),
                  title: Text(n.title),
                  subtitle:
                      Text('${n.body}\n${Formatters.dateTime(n.createdAt)}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(n.id),
                  ),
                  onTap: n.read
                      ? null
                      : () => ref
                          .read(notificationRepositoryProvider)
                          .markRead(n.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BroadcastDialog extends ConsumerStatefulWidget {
  const _BroadcastDialog();

  @override
  ConsumerState<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends ConsumerState<_BroadcastDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final companyId = ref.read(currentUserProvider).valueOrNull?.companyId ??
          AppConstants.defaultCompanyId;
      final count =
          await ref.read(notificationRepositoryProvider).broadcastToClients(
                companyId: companyId,
                title: _title.text.trim(),
                body: _body.text.trim(),
              );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sent to $count client(s).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Broadcast failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Broadcast to clients'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 96).clamp(260.0, 420.0).toDouble(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send'),
        ),
      ],
    );
  }
}
