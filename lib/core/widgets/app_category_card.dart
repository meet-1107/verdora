import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_image.dart';

/// A category tile (image or monogram + name + subtitle). Dumb widget: pass
/// display values and an [onTap]; no feature dependencies.
class AppCategoryCard extends StatelessWidget {
  const AppCategoryCard({
    super.key,
    required this.name,
    this.subtitle = 'Browse',
    this.imageUrl,
    this.onTap,
    this.width = 150,
  });

  final String name;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _leading(scheme),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading(ColorScheme scheme) {
    final provider = appImageProvider(imageUrl);
    if (provider != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image(
          image: provider,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _monogram(scheme),
        ),
      );
    }
    return _monogram(scheme);
  }

  Widget _monogram(ColorScheme scheme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}
