import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData forConsumer(BuildContext context) =>
      _override(context, AppColors.consumerBlue);

  static ThemeData forOwner(BuildContext context) =>
      _override(context, AppColors.primary);

  // Inherits all root ThemeData settings (fonts, scaffoldBackground, appBarTheme, etc.)
  // and only overrides the primary color + nav bar indicator/icon colors.
  static ThemeData _override(BuildContext context, Color primary) {
    final base = Theme.of(context);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: primary),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: primary.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? IconThemeData(color: primary)
              : null,
        ),
      ),
    );
  }
}
