import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

/// Plus Jakarta Sans — a rounder, heavier fintech-style face used only on
/// the newly redesigned "premium" screens (My Wallet, Refer & Earn), not
/// swapped into the shared [AppTypography] tokens the rest of the app
/// relies on (Sora/Inter), so this stays additive rather than a global
/// typography change.
TextStyle premiumFont(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size.sp,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}
