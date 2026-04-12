import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  // Display - big numbers
  static TextStyle displayLg = GoogleFonts.spaceGrotesk(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
    letterSpacing: -1.5,
  );

  // Headline - section titles
  static TextStyle headlineMd = GoogleFonts.spaceGrotesk(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
    letterSpacing: -0.5,
  );

  static TextStyle headlineSm = GoogleFonts.spaceGrotesk(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
  );

  // Body - desciptions, general text
  static TextStyle bodyLg = GoogleFonts.manrope(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.onSurface,
  );

  static TextStyle bodySm = GoogleFonts.manrope(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.onSurfaceVariant,
  );

  // Label - timestamp, mircodata
  static TextStyle labelSm = GoogleFonts.manrope(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurfaceVariant,
  );
  
}