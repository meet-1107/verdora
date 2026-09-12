import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// Centered loading spinner. On a slow connection the spinner can linger, so
/// after [slowAfter] a gentle "please wait" hint appears so the user knows the
/// app is still working and hasn't frozen.
class LoadingView extends StatefulWidget {
  const LoadingView({
    super.key,
    this.message,
    this.slowAfter = const Duration(seconds: 4),
  });

  final String? message;

  /// How long to wait before showing the slow-connection hint.
  final Duration slowAfter;

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (widget.message != null) ...[
              const SizedBox(height: 16),
              Text(widget.message!, style: theme.textTheme.bodyMedium),
            ],
            // Slow-connection reassurance.
            AnimatedOpacity(
              opacity: _slow ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_tethering,
                        size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 6),
                    Text('Slow connection — please wait…',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Friendly empty-state placeholder.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Whether [error] looks like a connectivity / slow-network problem rather than
/// a genuine bug — so we can show a reassuring "check your connection" message
/// with a Reload button instead of a scary technical error.
bool isConnectionError(Object error) {
  if (error is FirebaseException) {
    const netCodes = {
      'unavailable',
      'deadline-exceeded',
      'network-request-failed',
      'resource-exhausted',
      'aborted',
      'cancelled',
    };
    if (netCodes.contains(error.code)) return true;
  }
  final s = error.toString().toLowerCase();
  return s.contains('unavailable') ||
      s.contains('network') ||
      s.contains('timed out') ||
      s.contains('timeout') ||
      s.contains('socket') ||
      s.contains('connection') ||
      s.contains('host lookup') ||
      s.contains('offline');
}

/// Error placeholder with optional retry/reload. Connectivity problems get a
/// friendly, non-technical message; unexpected errors still show their detail.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isNet = isConnectionError(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isNet ? Icons.wifi_off_rounded : Icons.error_outline,
                size: 56, color: isNet ? scheme.primary : scheme.error),
            const SizedBox(height: 16),
            Text(isNet ? 'You appear to be offline' : 'Something went wrong',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                isNet
                    ? 'Your internet looks slow or disconnected. Check your '
                        'connection and reload.'
                    : '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(isNet ? 'Reload' : 'Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
