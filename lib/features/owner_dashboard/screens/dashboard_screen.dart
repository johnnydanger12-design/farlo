import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_outlined, size: 64, color: AppColors.textHint),
            SizedBox(height: 12),
            Text('Owner Dashboard — Phase 5'),
          ],
        ),
      ),
    );
  }
}
