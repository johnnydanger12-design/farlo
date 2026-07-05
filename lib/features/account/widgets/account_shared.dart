import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

// ARCH-4 (code-quality.md): extracted out of the 1452-line account_screen.dart.

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.textHint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Standard bottom sheet container: rounded top corners, padded, respects keyboard.
Widget buildSheetContainer({
  required BuildContext context,
  required Widget child,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return Container(
    decoration: BoxDecoration(
      color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    ),
    padding: EdgeInsets.fromLTRB(
      24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
    child: child,
  );
}
