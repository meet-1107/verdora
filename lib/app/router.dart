import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/admin_shell.dart';
import '../core/widgets/app_shell.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/client/presentation/client_categories_screen.dart';
import '../features/client/presentation/client_home_dashboard_screen.dart';
import '../features/client/presentation/client_orders_screen.dart';
import '../features/client/presentation/client_profile_screen.dart';
import '../features/dashboard/presentation/admin_dashboard_screen.dart';
import '../features/discounts/presentation/discounts_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/orders/presentation/admin_orders_screen.dart';
import '../features/parties/presentation/parties_screen.dart';
import '../features/products/presentation/products_screen.dart';
import '../features/raw_materials/presentation/raw_materials_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/warehouse/presentation/warehouse_screen.dart';

part 'router_shells.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// A [Listenable] that bumps whenever a set of providers change, so go_router
/// re-runs its redirect on auth/profile transitions.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(currentUserProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => _resolveRedirect(ref, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      _adminShellRoute(),
      _clientShellRoute(),
    ],
  );
});

/// Pure routing decision shared by the redirect. Returns the location to
/// redirect to, or `null` to stay put.
String? _resolveRedirect(Ref ref, String loc) {
  final authState = ref.read(authStateProvider);

  // Auth still resolving -> wait on splash.
  if (authState.isLoading) return loc == '/splash' ? null : '/splash';

  final signedIn = authState.valueOrNull != null;
  if (!signedIn) return loc == '/login' ? null : '/login';

  // Signed in: resolve profile/role.
  final profile = ref.read(currentUserProvider);
  if (profile.isLoading) return loc == '/splash' ? null : '/splash';

  final appUser = profile.valueOrNull;
  if (appUser == null) return loc == '/login' ? null : '/login';

  final isAdmin = appUser.role.isAdminSide;
  final home = isAdmin ? '/admin/dashboard' : '/client/home';

  // Send freshly authenticated users to their home.
  if (loc == '/login' || loc == '/splash' || loc == '/') return home;

  // Guard cross-role access.
  if (loc.startsWith('/admin') && !isAdmin) return '/client/home';
  if (loc.startsWith('/client') && isAdmin) return '/admin/dashboard';

  return null;
}
