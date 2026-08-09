import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/activity_repository.dart';
import '../domain/activity_log.dart';

final activityLogsProvider = StreamProvider<List<ActivityLog>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(activityRepositoryProvider).watchRecent(user.companyId);
});

class ActivityLogsScreen extends ConsumerWidget {
  const ActivityLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(activityLogsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity Logs')),
      body: logs.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(activityLogsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyView(
                message: 'No activity recorded yet.',
                icon: Icons.history_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = list[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle_outline),
                title: Text('${l.action}'
                    '${l.target != null ? ' · ${l.target}' : ''}'),
                subtitle: Text('${l.userName} · '
                    '${Formatters.dateTime(l.createdAt)}'),
              );
            },
          );
        },
      ),
    );
  }
}
