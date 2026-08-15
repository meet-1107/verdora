import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/notifications/data/notification_repository.dart';
import '../features/settings/presentation/settings_providers.dart'
    show companySettingsProvider, cacheBranding, themeModeProvider;
import 'router.dart';
import 'theme.dart';

/// Back-button dispatcher that never lets a pop crash the app.
///
/// go_router 14.x throws `Bad state: No element` from
/// `GoRouterDelegate._findCurrentNavigator` (`currentConfiguration.matches.last`)
/// when the system back button is dispatched while the route match list is
/// momentarily empty — which happens during sign-out, as the client
/// `StatefulShellRoute` is torn down before `/login` is mounted. That exception
/// escapes on the platform back-button channel and causes Android to finish the
/// Activity (the app closes to the launcher / black screen). Catching it here
/// and reporting the pop as "handled" keeps the process alive so the auth
/// redirect can settle on the login screen.
class _SafeBackButtonDispatcher extends RootBackButtonDispatcher {
  @override
  Future<bool> didPopRoute() async {
    try {
      return await super.didPopRoute();
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Guarded back-button pop: $error\n$stack');
      }
      return true; // handled -> Android must not finish the Activity
    }
  }
}

final _backButtonDispatcher = _SafeBackButtonDispatcher();

class B2bApp extends ConsumerWidget {
  const B2bApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Register the device's FCM token whenever a user signs in.
    ref.listen(currentUserProvider, (prev, next) {
      final user = next.valueOrNull;
      if (user != null) {
        ref.read(notificationRepositoryProvider).registerToken(user.uid);
      }
    });

    // Cache company branding (logo + name) so the pre-auth login screen can
    // show it on the next launch.
    ref.listen(companySettingsProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s != null && (s.logoUrl.isNotEmpty || s.name.isNotEmpty)) {
        cacheBranding(s.logoUrl, s.name);
      }
    });
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Use the router's parts individually so we can substitute a crash-proof
      // back-button dispatcher (see [_SafeBackButtonDispatcher]).
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      backButtonDispatcher: _backButtonDispatcher,
    );
  }
}
