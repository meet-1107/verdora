import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Verdora buttons. Thin wrappers over the themed Material buttons that add a
/// consistent inline loading spinner, optional leading icon, and full-width
/// option. Heights/radii/colours all come from the theme — do not restyle.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonContent(
      label: label,
      icon: icon,
      loading: loading,
      spinnerColor: Theme.of(context).colorScheme.onPrimary,
    );
    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );
    return fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

class AppOutlinedButton extends StatelessWidget {
  const AppOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonContent(
      label: label,
      icon: icon,
      loading: loading,
      spinnerColor: Theme.of(context).colorScheme.primary,
    );
    final button = OutlinedButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );
    return fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Destructive action button (red).
class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
      ),
      onPressed: loading ? null : onPressed,
      child: _ButtonContent(
        label: label,
        icon: icon,
        loading: loading,
        spinnerColor: Colors.white,
      ),
    );
    return fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.loading,
    required this.spinnerColor,
    this.icon,
  });

  final String label;
  final bool loading;
  final Color spinnerColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
      );
    }
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
