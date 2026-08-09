/// Verdora Design System — 8dp spacing scale and radii. Never use arbitrary
/// paddings/radii; pick from these.
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;
  static const giant = 48.0;
  static const massive = 64.0;

  // Page padding by breakpoint.
  static const pagePaddingMobile = 16.0;
  static const pagePaddingTablet = 24.0;
  static const pagePaddingDesktop = 32.0;

  /// Max content width on large screens (never stretch cards edge-to-edge).
  static const maxContentWidth = 1400.0;
}

/// Corner radii per component type.
class AppRadius {
  AppRadius._();

  static const card = 20.0;
  static const button = 16.0;
  static const dialog = 20.0;
  static const bottomSheet = 28.0;
  static const textField = 14.0;
  static const imageCard = 18.0;
  static const chip = 10.0;
  static const search = 16.0;
}
