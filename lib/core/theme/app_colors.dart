import 'package:flutter/material.dart';

/// Verdora Design System — color tokens. These are the ONLY source of colour
/// in the app; screens must read colours from the theme (`ColorScheme`) or from
/// [AppColors]/[AppStatusPalette], never hardcode hex values.
class AppColors {
  AppColors._();

  // Brand — professional ERP blue.
  static const primary = Color(0xFF1976D2);
  static const primaryLight = Color(0xFF42A5F5);
  static const primaryContainer = Color(0xFFE3F2FD);

  // Kept green tokens for "good/positive" status semantics (approved, in-stock).
  static const brandGreen = Color(0xFF2E7D32);

  // Neutrals
  static const background = Color(0xFFFAFAFA);
  static const surface = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const divider = Color(0xFFEEEEEE);
  static const border = Color(0xFFE0E0E0);

  // Semantic
  static const success = Color(0xFF43A047);
  static const warning = Color(0xFFFB8C00);
  static const error = Color(0xFFD32F2F);
  static const info = Color(0xFF1976D2);

  // Text
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const hint = Color(0xFF9E9E9E);
  static const disabled = Color(0xFFBDBDBD);

  // Dark-mode neutrals (kept close to spec while remaining legible).
  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1E1E1E);
  static const darkCard = Color(0xFF242424);
  static const darkDivider = Color(0xFF2E2E2E);
}

/// Status → colour mapping (orders, stock, etc.). Use [AppStatusPalette.forOrder]
/// so every status chip in the app is coloured identically.
class AppStatusPalette {
  AppStatusPalette._();

  static const pending = AppColors.warning; // Orange
  static const approved = AppColors.brandGreen; // Green (positive state)
  static const modifiedApproved = Color(0xFF00897B); // Teal (approved w/ edits)
  static const packing = Color(0xFF0288D1); // Light blue (distinct from brand)
  static const packed = Color(0xFF3949AB); // Indigo
  static const dispatched = Color(0xFF7B1FA2); // Purple
  static const delivered = Color(0xFF2E7D32); // Dark green
  static const completed = AppColors.success; // Green
  static const cancelled = AppColors.error; // Red
  static const rejected = AppColors.error; // Red
  static const returned = Color(0xFF6D4C41); // Brown
  static const draft = AppColors.textSecondary; // Grey

  /// Resolve a colour from an order-status string value (see OrderStatus.value).
  static Color forOrder(String statusValue) {
    switch (statusValue) {
      case 'pending':
        return pending;
      case 'approved':
        return approved;
      case 'modified_approved':
        return modifiedApproved;
      case 'packing':
        return packing;
      case 'packed':
        return packed;
      case 'dispatched':
        return dispatched;
      case 'delivered':
        return delivered;
      case 'completed':
        return completed;
      case 'cancelled':
        return cancelled;
      case 'rejected':
        return rejected;
      case 'returned':
        return returned;
      default:
        return draft;
    }
  }
}
