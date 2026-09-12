import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
class AppShell extends StatefulWidget {
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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBack;

  void _go(int index) => widget.navigationShell.goBranch(
        index,
        initialLocation: index == widget.navigationShell.currentIndex,
      );

  /// Back button: first press shows a hint, a second press within 2 seconds
  /// exits the app. Applies to every client tab.
  void _onBack(bool didPop) {
    if (didPop) return;
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Press back again to exit'),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final destinations = widget.destinations;
    final title = widget.title;
    final trailing = widget.trailing;
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
