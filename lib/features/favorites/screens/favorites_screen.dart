import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 64, color: AppColors.textHint),
            SizedBox(height: 12),
            Text('Favorites — Phase 4'),
          ],
        ),
      ),
    );
  }
}
