import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/food_truck.dart';

// ARCH-4 (code-quality.md): extracted out of the 1106-line map_screen.dart.

class OffScreenIndicator extends StatelessWidget {
  const OffScreenIndicator({super.key, required this.truck, required this.onTap});
  final FoodTruck truck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '${truck.name}, off screen',
      button: true,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: primary, width: 2.5),
          color: primary,
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.45),
              blurRadius: 10,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: truck.logoUrl != null
              ? Image.network(
                  truck.logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.storefront_outlined, color: Colors.white, size: 22),
                )
              : const Icon(Icons.storefront_outlined, color: Colors.white, size: 22),
        ),
      ),
      ),
    );
  }
}

class TruckPin extends StatelessWidget {
  const TruckPin({super.key, required this.isOpen, this.logoUrl, this.sessionStartedAt});

  final bool isOpen;
  final String? logoUrl;
  final DateTime? sessionStartedAt;

  String? get _badge {
    if (sessionStartedAt == null) return null;
    final diff = DateTime.now().difference(sessionStartedAt!);
    if (diff.inMinutes < 10) return null;
    if (diff.inDays >= 1) return 'Opened ${diff.inDays}d';
    if (diff.inHours >= 1) return 'Opened ${diff.inHours}h';
    return 'Opened ${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isOpen ? Theme.of(context).colorScheme.primary : AppColors.textHint;
    final badge = _badge;
    final circle = Container(
      width: 44,
      height: 44,
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
            ? Image.network(
                logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _PinFallback(accentColor: accentColor),
              )
            : _PinFallback(accentColor: accentColor),
      ),
    );

    if (badge == null) return circle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _PinFallback extends StatelessWidget {
  const _PinFallback({required this.accentColor});
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: accentColor,
      child: const Center(child: Icon(Icons.storefront_outlined, color: Colors.white, size: 24)),
    );
  }
}
