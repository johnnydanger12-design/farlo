import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../services/storage_service.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../models/operating_hours.dart';

// ARCH-4 (code-quality.md): extracted out of the 1425-line truck_profile_screen.dart.

class PhotoCarousel extends StatelessWidget {
  const PhotoCarousel({
    super.key,
    required this.urls,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
  });

  final List<String> urls;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: controller,
          itemCount: urls.length,
          onPageChanged: onPageChanged,
          itemBuilder: (_, i) => CachedNetworkImage(
            imageUrl: transformedImageUrl(urls[i], width: 1200),
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const LogoHero(logoUrl: null),
          ),
        ),
        if (urls.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(urls.length, (i) {
                final active = i == currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: active ? 1.0 : 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class LogoHero extends StatelessWidget {
  const LogoHero({super.key, required this.logoUrl});
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.secondary,
      child: Center(
        child: logoUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: transformedImageUrl(logoUrl!, width: 300, height: 300),
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const TruckIconPlaceholder(),
                ),
              )
            : const TruckIconPlaceholder(),
      ),
    );
  }
}

class TruckIconPlaceholder extends StatelessWidget {
  const TruckIconPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.storefront_outlined, color: Colors.white54, size: 72);
  }
}

class FollowerCount extends ConsumerWidget {
  const FollowerCount({super.key, required this.truckId});
  final String truckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(truckFollowerCountProvider(truckId));
    return countAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (count) {
        final label = count == 1 ? '1 follower' : '$count followers';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border_rounded, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.caption),
          ],
        );
      },
    );
  }
}

class OpenBadge extends StatelessWidget {
  const OpenBadge({super.key, required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.openGreen : AppColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isOpen ? 'Open' : 'Closed',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class HoursTable extends StatelessWidget {
  const HoursTable({super.key, required this.hours});
  final List<OperatingHours> hours;

  @override
  Widget build(BuildContext context) {
    final todayIndex = DateTime.now().weekday % 7; // weekday: Mon=1…Sun=7 → Sun=0
    return Column(
      children: hours.map((h) {
        final isToday = h.dayOfWeek == todayIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  h.dayName,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isToday ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
              Text(
                h.hoursDisplay,
                style: AppTextStyles.bodySmall.copyWith(
                  color: h.isClosed ? AppColors.textHint : null,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Today',
                    style: AppTextStyles.caption.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class SectionSpacer extends StatelessWidget {
  const SectionSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(child: SizedBox(height: 8));
  }
}
