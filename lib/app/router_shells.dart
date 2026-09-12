part of 'router.dart';

const _clientDestinations = <ShellDestination>[
  ShellDestination(
      label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
  ShellDestination(
      label: 'Products',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view),
  ShellDestination(
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long),
  ShellDestination(
      label: 'Alerts',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications),
  ShellDestination(
      label: 'Profile', icon: Icons.person_outline, selectedIcon: Icons.person),
];

/// Sign-out action placed at the bottom of the admin rail.
class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
      onPressed: () async {
        final router = GoRouter.of(context);
        await ref.read(authRepositoryProvider).signOut();
        router.go('/login');
      },
    );
  }
}

StatefulShellRoute _adminShellRoute() {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, navigationShell) =>
        AdminShell(navigationShell: navigationShell),
    branches: [
      _branch('/admin/dashboard', const AdminDashboardScreen()),
      _branch('/admin/orders', const AdminOrdersScreen()),
      _branch('/admin/products', const ProductsScreen()),
      _branch('/admin/categories', const CategoriesScreen()),
      _branch('/admin/inventory', const InventoryScreen()),
      _branch('/admin/parties', const PartiesScreen()),
      _branch('/admin/discounts', const DiscountsScreen()),
      _branch('/admin/reports', const ReportsScreen()),
      _branch('/admin/settings', const SettingsScreen()),
      _branch('/admin/warehouse', const WarehouseScreen()),
      _branch('/admin/raw-materials', const RawMaterialsScreen()),
    ],
  );
}

StatefulShellRoute _clientShellRoute() {
  return StatefulShellRoute.indexedStack(
    builder: (context, state, navigationShell) => AppShell(
      navigationShell: navigationShell,
      destinations: _clientDestinations,
      title: 'Store',
      trailing: const _LogoutButton(),
    ),
    branches: [
      _branch('/client/home', const ClientHomeDashboardScreen()),
      _branch('/client/products', const ClientCategoriesScreen()),
      _branch('/client/orders', const ClientOrdersScreen()),
      _branch('/client/notifications', const NotificationsScreen()),
      _branch('/client/profile', const ClientProfileScreen()),
    ],
  );
}

StatefulShellBranch _branch(String path, Widget child) {
  return StatefulShellBranch(
    routes: [GoRoute(path: path, builder: (_, __) => child)],
  );
}
