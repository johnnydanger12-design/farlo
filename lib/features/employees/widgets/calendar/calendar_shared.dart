import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

// Shared across calendar_screen.dart and its extracted widget files
// (ARCH-4 — decomposed out of the 1448-line calendar_screen.dart).

const colBooking = AppColors.primary;
const colScheduled = Color(0xFF6366F1);
const colWorked = Color(0xFF6B7280);
const colLocation = Color(0xFF0D9488); // teal

String fmtTime(DateTime dt) {
  final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour < 12 ? 'am' : 'pm';
  return '$h:$m $ampm';
}
