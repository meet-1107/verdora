import 'package:flutter/material.dart';

import 'app_image.dart';

/// A rounded image thumbnail with a graceful icon fallback (used in admin
/// category / subcategory / product / inventory lists). Renders inline base64
/// images or network URLs; shows the icon until an image is added.
class AppThumb extends StatelessWidget {
  const AppThumb({
    super.key,
    this.url,
    this.size = 48,
    this.icon = Icons.image_outlined,
  });

  final String? url;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget fallback() => Container(
          width: size,
          height: size,
          color: scheme.surfaceContainerHighest,
          child: Icon(icon, color: scheme.onSurfaceVariant, size: size * 0.5),
        );
    final provider = appImageProvider(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: provider == null
          ? fallback()
          : Image(
              image: provider,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
            ),
    );
  }
}
