import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'responsive.dart';

/// A single navigation destination for the adaptive shell.
class ShellDestination {
  const ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Adaptive navigation shell used by both the admin and client apps.
///
/// * Desktop / tablet -> [NavigationRail] (extended on wide screens).
/// * Mobile -> [NavigationBar] at the bottom.
///
/// Works with go_router's [StatefulNavigationShell] for stateful branch
/// navigation (each tab keeps its own navigation stack).
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.destinations,
    required this.title,
    this.trailing,
  });

  final StatefulNavigationShell navigationShell;
  final List<ShellDestination> destinations;
  final String title;
  final Widget? trailing;

  void _go(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;

    if (Responsive.isMobile(context)) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _go,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final extended = Responsive.isDesktop(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 220,
            selectedIndex: index,
            onDestinationSelected: _go,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_rounded,
                      color: Theme.of(context).colorScheme.primary),
                  if (extended) ...[
                    const SizedBox(height: 8),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ],
              ),
            ),
            trailing: trailing == null
                ? null
                : Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: trailing,
                      ),
                    ),
                  ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
