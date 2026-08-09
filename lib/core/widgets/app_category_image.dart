import 'package:flutter/material.dart';

import 'app_image.dart';

/// Square, rounded category image (inline base64 or network) with a branded
/// fallback icon.
class AppCategoryImage extends StatelessWidget {
  const AppCategoryImage({
    super.key,
    this.imageUrl,
    this.size = 84,
    this.icon = Icons.category_outlined,
  });

  final String? imageUrl;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.42, color: scheme.onPrimaryContainer),
    );

    final provider = appImageProvider(imageUrl);
    if (provider == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
