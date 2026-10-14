import 'package:flutter/material.dart';

/// Design tokens and Material 3 theme implementation for AgriPrecision Botanical.
/// Based on Google Stitch project: MangoCount UI Design System (#6183948359442346065).
/// "Field notebook meets precision optical instrument."
class AppColors {
  // Light Mode Palette (Stitch "AgriPrecision Botanical" White & Green Accent)
  static const Color canvasCream = Color(0xFFFFFFFF); // Clean White Canvas
  static const Color surfaceWhite = Color(0xFFFFFFFF); // Pure White Surface
  static const Color primaryGreen =
      Color(0xFF1F5D3F); // Deep Botanical Green Accent
  static const Color primaryGreenLight =
      Color(0xFF2E7D32); // Vibrant Shoot Green
  static const Color ripeAmber = Color(0xFFF59E1B); // Harvest Ripe Amber
  static const Color unripeGreen = Color(0xFF5FA84A); // Vegetative Shoot Green
  static const Color overRipeEarth = Color(0xFF865300); // Earth Warm Amber
  static const Color charcoalText =
      Color(0xFF1B2A21); // Archival Evergreen-Charcoal
  static const Color mutedGraphite =
      Color(0xFF5E6F63); // Field Note Secondary Graphite
  static const Color errorCrimson = Color(0xFFC0392B); // High-vis Crimson
  static const Color outlineTint = Color(0xFFD5E7D9); // Hairline division
  static const Color surfaceContainer =
      Color(0xFFE8F5E9); // Botanical Soft Green Container
  static const Color surfaceContainerLow =
      Color(0xFFF4F9F5); // Crisp Light Botanical Surface

  // Sunset Action Gradient: Reserved for primary capture actions & highlight gauges
  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [Color(0xFFFF8A3D), Color(0xFFF5C33B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Emerald Botanical Gradient: For hero banners and status cards
  static const LinearGradient botanicalGradient = LinearGradient(
    colors: [Color(0xFF1F5D3F), Color(0xFF13422C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark Mode Palette (Preserved fallbacks)
  static const Color darkCanopy = Color(0xFF0E1712);
  static const Color darkSurface = Color(0xFF17231C);
  static const Color darkPrimaryMint = Color(0xFF7FD1A0);
  static const Color darkRipeAmber = Color(0xFFFFB547);
  static const Color darkUnripeGreen = Color(0xFF86CF70);
  static const Color darkTextParchment = Color(0xFFEAF3EC);
  static const Color darkMutedMist = Color(0xFF9DB2A4);
  static const Color darkOutline = Color(0xFF2A3A30);
}

class AppShapes {
  /// Signature Asymmetrical Leaf-Cut Cards: 24px on three corners, 6px taper on top-right corner.
  static const BorderRadius leafCut = BorderRadius.only(
    topLeft: Radius.circular(24),
    topRight: Radius.circular(6),
    bottomLeft: Radius.circular(24),
    bottomRight: Radius.circular(24),
  );

  static const RoundedRectangleBorder leafCutShape = RoundedRectangleBorder(
    borderRadius: leafCut,
  );

  /// Lower viewport inspection sheets: 28px top contours
  static const BorderRadius consoleSheet = BorderRadius.vertical(
    top: Radius.circular(28),
  );

  /// Stadium / Pill shapes for sensor tags and chips
  static const BorderRadius pill = BorderRadius.all(Radius.circular(9999));
}

class AppTheme {
  static ThemeData get lightTheme {
    const baseColorScheme = ColorScheme.light(
      primary: AppColors.primaryGreen,
      onPrimary: Colors.white,
      primaryContainer: AppColors.surfaceContainer,
      onPrimaryContainer: AppColors.primaryGreen,
      secondary: AppColors.ripeAmber,
      onSecondary: AppColors.charcoalText,
      secondaryContainer: Color(0xFFFFF3E0),
      onSecondaryContainer: Color(0xFF694000),
      tertiary: AppColors.unripeGreen,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.surfaceContainerLow,
      onTertiaryContainer: Color(0xFF094600),
      surface: AppColors.surfaceWhite,
      onSurface: AppColors.charcoalText,
      surfaceDim: Color(0xFFE8EFEA),
      surfaceBright: AppColors.surfaceWhite,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: Color(0xFFDEF0E1),
      surfaceContainerHighest: Color(0xFFD5E7D9),
      outline: AppColors.mutedGraphite,
      outlineVariant: AppColors.outlineTint,
      error: AppColors.errorCrimson,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: baseColorScheme,
      scaffoldBackgroundColor: Colors.white,
      fontFamilyFallback: const ['Georgia', 'serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.primaryGreen),
        titleTextStyle: TextStyle(
          color: AppColors.charcoalText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          fontFamilyFallback: ['Georgia', 'serif'],
        ),
      ),
      cardTheme: CardTheme(
        color: AppColors.surfaceWhite,
        elevation: 0,
        shape: AppShapes.leafCutShape.copyWith(
          side: const BorderSide(color: Color(0x261F5D3F), width: 1.2),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: const ChipThemeData(
        shape: StadiumBorder(),
        backgroundColor: AppColors.surfaceContainer,
        labelStyle: TextStyle(
          color: AppColors.primaryGreen,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: Color(0x331F5D3F)),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.ripeAmber,
        inactiveTrackColor: AppColors.outlineTint,
        thumbColor: AppColors.primaryGreen,
        overlayColor: AppColors.primaryGreen.withOpacity(0.12),
        valueIndicatorColor: AppColors.charcoalText,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF4F9F5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x261F5D3F)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x261F5D3F)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.primaryGreen, width: 1.8),
        ),
        labelStyle:
            const TextStyle(color: AppColors.mutedGraphite, fontSize: 13),
      ),
    );
  }

  /// App follows the Stitch "AgriPrecision Botanical" White & Green Accent theme.
  static ThemeData get darkTheme => lightTheme;
}
