import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map, size: 64, color: AppColors.textHint),
            SizedBox(height: 12),
            Text('Map — Phase 2'),
          ],
        ),
      ),
    );
  }
}
