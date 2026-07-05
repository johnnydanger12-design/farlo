import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../../services/storage_service.dart';

/// Circle map marker showing a truck's logo (or a fallback icon).
/// Used on the consumer map, owner dashboard mini-map, and employee dashboard mini-map.
class TruckMapPin extends StatelessWidget {
  const TruckMapPin({
    super.key,
    required this.isOpen,
    this.logoUrl,
    this.size = 44,
  });

  final bool isOpen;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accentColor =
        isOpen ? Theme.of(context).colorScheme.primary : AppColors.textHint;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 2.5),
        color: accentColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: logoUrl != null
            ? CachedNetworkImage(
                imageUrl: transformedImageUrl(logoUrl!, width: 88, height: 88),
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _Fallback(accentColor: accentColor),
              )
            : _Fallback(accentColor: accentColor),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.accentColor});
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: accentColor,
      child: const Center(
        child: Icon(Icons.storefront_outlined, color: Colors.white, size: 24),
      ),
    );
  }
}
