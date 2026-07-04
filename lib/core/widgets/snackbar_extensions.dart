import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Collapses the 60+ near-identical `ScaffoldMessenger.of(context).showSnackBar(...)`
/// call sites found across the app into 3 consistent helpers, and standardizes
/// error-snackbar color (some sites used a raw `Colors.red`, others `AppColors.error`).
extension SnackBarExtensions on BuildContext {
  void showError(String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    bool showCloseIcon = false,
    SnackBarBehavior? behavior,
  }) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: duration,
        action: action,
        showCloseIcon: showCloseIcon,
        behavior: behavior,
      ),
    );
  }

  void showSuccess(String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Color? backgroundColor,
    SnackBarBehavior? behavior,
  }) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
        backgroundColor: backgroundColor,
        behavior: behavior,
      ),
    );
  }

  /// Neutral/informational snackbar — same styling as showSuccess (the
  /// default SnackBar theme), named separately so call sites read correctly
  /// even when the message isn't reporting a successful action.
  void showInfo(String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    bool showCloseIcon = false,
    SnackBarBehavior? behavior,
  }) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
        showCloseIcon: showCloseIcon,
        behavior: behavior,
      ),
    );
  }
}

/// Strips technical prefixes a raw caught exception's toString() carries
/// (e.g. "Exception: ", "PostgrestException(message: ...)") so catch blocks
/// that currently show raw exception text to the user (code-quality.md
/// §2.12/§2.16) have a one-line way to show something more human instead.
/// Callers that already build a curated message should keep doing so — this
/// is only for the sites that were showing `e.toString()`/`'Error: $e'` raw.
String sanitizeErrorMessage(Object error) {
  var text = error.toString();
  const prefixes = ['Exception: ', 'AuthException: ', 'PostgrestException: '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length);
      break;
    }
  }
  return text;
}
