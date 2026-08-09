import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Simple responsive helpers for building adaptive (mobile/tablet/desktop) UI.
class Responsive {
  Responsive._();

  static bool isMobile(BuildContext c) =>
      MediaQuery.sizeOf(c).width < AppConstants.mobileBreakpoint;

  static bool isTablet(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return w >= AppConstants.mobileBreakpoint &&
        w < AppConstants.tabletBreakpoint;
  }

  static bool isDesktop(BuildContext c) =>
      MediaQuery.sizeOf(c).width >= AppConstants.tabletBreakpoint;
}

/// Builds a different widget per breakpoint. [tablet] falls back to whichever
/// of [desktop]/[mobile] is provided when omitted.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) return desktop;
    if (Responsive.isTablet(context)) return tablet ?? desktop;
    return mobile;
  }
}
