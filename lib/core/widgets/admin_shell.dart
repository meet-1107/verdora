import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/inventory/presentation/inventory_providers.dart';
import '../constants/app_constants.dart';
import '../theme/app_spacing.dart';
import 'responsive.dart';

/// Key to the admin shell's Scaffold so screen app bars can open the drawer
/// (mobile layout only).
final GlobalKey<ScaffoldState> adminScaffoldKey = GlobalKey<ScaffoldState>();

/// Branch index order in the admin StatefulShellRoute. Keep in sync with the
/// router's `_adminShellRoute()` branch order.
class AdminBranch {
  AdminBranch._();
  static const dashboard = 0;
  static const orders = 1;
  static const products = 2;
  static const categories = 3;
  static const inventory = 4;
  static const parties = 5;
  static const discounts = 6;
  static const reports = 7;
  static const settings = 8;
  static const warehouse = 9;
  static const rawMaterial = 10;
}

/// A single admin navigation item.
class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon, this.branch);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int branch;
}

/// A labelled group of nav items in the sidebar.
class _NavGroup {
  const _NavGroup(this.title, this.items);
  final String? title;
  final List<_NavItem> items;
}

const _navGroups = <_NavGroup>[
  _NavGroup(null, [
    _NavItem('Dashboard', Icons.dashboard_outlined, Icons.dashboard,
        AdminBranch.dashboard),
  ]),
  _NavGroup('Operations', [
    _NavItem('Orders', Icons.receipt_long_outlined, Icons.receipt_long,
        AdminBranch.orders),
    _NavItem('Warehouse', Icons.warehouse_outlined, Icons.warehouse,
        AdminBranch.warehouse),
    _NavItem('Dealers', Icons.groups_outlined, Icons.groups,
        AdminBranch.parties),
    _NavItem('Inventory', Icons.inventory_2_outlined, Icons.inventory_2,
        AdminBranch.inventory),
    _NavItem('Raw Material', Icons.science_outlined, Icons.science,
        AdminBranch.rawMaterial),
  ]),
  _NavGroup('Catalog', [
    _NavItem('Products', Icons.category_outlined, Icons.category,
        AdminBranch.products),
    _NavItem('Categories', Icons.folder_outlined, Icons.folder,
        AdminBranch.categories),
    _NavItem('Discounts', Icons.percent_outlined, Icons.percent,
        AdminBranch.discounts),
  ]),
  _NavGroup('Insights', [
    _NavItem('Reports', Icons.bar_chart_outlined, Icons.bar_chart,
        AdminBranch.reports),
  ]),
  _NavGroup('System', [
    _NavItem('Settings', Icons.settings_outlined, Icons.settings,
        AdminBranch.settings),
  ]),
];

/// The five primary destinations surfaced on the mobile bottom bar.
const _primaryMobile = <_NavItem>[
  _NavItem('Orders', Icons.receipt_long_outlined, Icons.receipt_long,
      AdminBranch.orders),
  _NavItem('Dealers', Icons.groups_outlined, Icons.groups, AdminBranch.parties),
  _NavItem('Inventory', Icons.inventory_2_outlined, Icons.inventory_2,
      AdminBranch.inventory),
  _NavItem('Products', Icons.category_outlined, Icons.category,
      AdminBranch.products),
  _NavItem('Reports', Icons.bar_chart_outlined, Icons.bar_chart,
      AdminBranch.reports),
];

/// Adaptive admin navigation shell.
///
/// * Wide screens (web / desktop / tablet) → a permanent ERP sidebar.
/// * Phone → a 5-item bottom bar plus a full menu drawer.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  bool? _collapsed; // null until first build resolves the default for the size.

  void _go(int branch) => widget.navigationShell.goBranch(
        branch,
        initialLocation: branch == widget.navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    // One-time cleanup: reset any negative stock cache to zero.
    ref.watch(zeroNegativeStockProvider);

    if (Responsive.isMobile(context)) {
      return Scaffold(
        key: adminScaffoldKey,
        drawer: _AdminDrawer(
            onSelect: _go, current: widget.navigationShell.currentIndex),
        body: widget.navigationShell,
        bottomNavigationBar: _AdminBottomBar(
            current: widget.navigationShell.currentIndex, onSelect: _go),
      );
    }

    // Wide layout: default collapsed on tablet, expanded on desktop.
    final collapsed = _collapsed ?? !Responsive.isDesktop(context);
    return Scaffold(
      body: Row(
        children: [
          _AdminSidebar(
            current: widget.navigationShell.currentIndex,
            collapsed: collapsed,
            onSelect: _go,
            onToggle: () => setState(() => _collapsed = !collapsed),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }
}

/// Opens the admin drawer (mobile only). Placed as the `leading` of an admin
/// screen's AppBar; renders nothing on wide layouts where the sidebar is always
/// visible.
class AdminMenuButton extends StatelessWidget {
  const AdminMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isMobile(context)) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onPressed: () => adminScaffoldKey.currentState?.openDrawer(),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop sidebar
// ---------------------------------------------------------------------------

class _AdminSidebar extends ConsumerWidget {
  const _AdminSidebar({
    required this.current,
    required this.collapsed,
    required this.onSelect,
    required this.onToggle,
  });

  final int current;
  final bool collapsed;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = collapsed ? 80.0 : 280.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: width,
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand header
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? AppSpacing.md : AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.inventory_2_rounded,
                      color: scheme.primary, size: 22),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppConstants.appName,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis),
                        Text('Admin console',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),

          // Menu
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (final group in _navGroups) ...[
                  if (!collapsed && group.title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
                      child: Text(group.title!.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.8,
                          )),
                    )
                  else if (group.title != null)
                    const SizedBox(height: AppSpacing.sm),
                  for (final item in group.items)
                    _SidebarTile(
                      item: item,
                      selected: current == item.branch,
                      collapsed: collapsed,
                      onTap: () => onSelect(item.branch),
                    ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),
          // Footer: collapse toggle + sign out
          _SidebarAction(
            icon: collapsed ? Icons.chevron_right : Icons.chevron_left,
            label: 'Collapse',
            collapsed: collapsed,
            onTap: onToggle,
          ),
          _SidebarAction(
            icon: Icons.logout,
            label: 'Sign out',
            collapsed: collapsed,
            danger: true,
            onTap: () async {
              final router = GoRouter.of(context);
              await ref.read(authRepositoryProvider).signOut();
              router.go('/login');
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    final tile = Container(
      margin: EdgeInsets.symmetric(
          horizontal: collapsed ? AppSpacing.sm : AppSpacing.md,
          vertical: 2),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : AppSpacing.md, vertical: 12),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(selected ? item.selectedIcon : item.icon,
                  size: 22,
                  color: selected ? scheme.onPrimaryContainer : fg),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? scheme.onPrimaryContainer : fg,
                      ),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!collapsed) return tile;
    return Tooltip(message: item.label, child: tile);
  }
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : AppSpacing.xl, vertical: 12),
        child: Row(
          mainAxisAlignment:
              collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            if (!collapsed) ...[
              const SizedBox(width: AppSpacing.md),
              Text(label, style: TextStyle(color: color, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile bottom bar + drawer (unchanged behaviour)
// ---------------------------------------------------------------------------

class _AdminBottomBar extends StatelessWidget {
  const _AdminBottomBar({required this.current, required this.onSelect});
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in _primaryMobile)
                Expanded(
                  child: _BottomItem(
                    label: item.label,
                    icon: item.icon,
                    selected: current == item.branch,
                    onTap: () => onSelect(item.branch),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon,
                size: 22,
                color: selected ? scheme.onPrimaryContainer : color),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              )),
        ],
      ),
    );
  }
}

class _AdminDrawer extends ConsumerWidget {
  const _AdminDrawer({required this.onSelect, required this.current});
  final ValueChanged<int> onSelect;
  final int current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget tile(_NavItem item) => ListTile(
          leading: Icon(current == item.branch ? item.selectedIcon : item.icon),
          title: Text(item.label),
          selected: current == item.branch,
          selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
          selectedColor: scheme.primary,
          onTap: () {
            Navigator.of(context).pop();
            onSelect(item.branch);
          },
        );

    return Drawer(
      width: 280,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_rounded, color: scheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppConstants.appName,
                          style: theme.textTheme.titleLarge),
                      Text('Admin console',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final group in _navGroups) ...[
              if (group.title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
                  child: Text(group.title!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      )),
                ),
              for (final item in group.items) tile(item),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                await ref.read(authRepositoryProvider).signOut();
                router.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
