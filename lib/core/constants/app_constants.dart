/// App-wide constants and configuration flags.
class AppConstants {
  AppConstants._();

  static const appName = 'Asian Plast';

  /// Single-tenant default. Every record carries [companyId] so the app is
  /// multi-tenant ready; until a company-switching UI exists, this default
  /// company id is used for the current deployment.
  static const defaultCompanyId = 'default';

  /// Client login: a Party ID is turned into a synthetic Firebase Auth email
  /// so both admin and client can use Firebase Email/Password auth.
  /// e.g. Party ID `P00102` -> `p00102@party.b2bsaas.app`
  static const partyEmailDomain = 'party.b2bsaas.app';

  static const invoicePrefix = 'INV';

  /// GST rate (percent) applied to the net amount (after all discounts) on a
  /// client purchase order and its generated invoice. Single tax slab for now.
  static const double gstRate = 18.0;

  /// Web Push certificate (VAPID) public key for FCM on web. Used by
  /// `getToken(vapidKey: ...)`; ignored on Android/iOS.
  static const webPushVapidKey =
      'BInV_sbf2hz3Me1-Hh5THcje4Q-oyRSxDOPAf7SyxQN3QSoEVo77HaNW6KhHP7Kfb93D_LjyBR-Silg7-IuuuD0';

  /// Responsive breakpoints (logical pixels).
  static const mobileBreakpoint = 600.0;
  static const tabletBreakpoint = 1024.0;
}
