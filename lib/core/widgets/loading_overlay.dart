import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black26,
      child: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}
