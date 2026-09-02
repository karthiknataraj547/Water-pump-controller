import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Minimalist Color Palette
  static const Color primary = Color(0xFF0EA5E9);       // Sky blue
  static const Color primaryLight = Color(0xFF7DD3FC);   // Light sky
  static const Color primaryDark = Color(0xFF0284C7);    // Deep sky
  static const Color accent = Color(0xFF22C55E);         // Sage green
  static const Color warning = Color(0xFFF59E0B);        // Amber
  static const Color danger = Color(0xFFEF4444);         // Rose
  static const Color dangerLight = Color(0xFFFCA5A5);

  // Dark Mode Surfaces — soft charcoal, not pitch black
  static const Color darkBg = Color(0xFF16161E);
  static const Color darkSurface = Color(0xFF1E1E2A);
  static const Color darkCard = Color(0xFF252536);
  static const Color darkCardBorder = Color(0xFF35354A);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);

  // Light Mode Surfaces — clean whites, minimal contrast
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Water colors for tank rendering
  static const Color waterBlue = Color(0xFF7DD3FC);
  static const Color waterBlueDark = Color(0xFF38BDF8);
  static const Color waterBlueDarkMode = Color(0xFF38BDF8);

  // Backward compatibility aliases
  static const Color primaryCyan = primary;
  static const Color primaryBlue = primaryDark;
  static const Color accentEmerald = accent;
  static const Color accentAmber = warning;
  static const Color accentRose = danger;

  static const LinearGradient hydroGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [accent, Color(0xFF16A34A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [danger, Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: darkSurface,
        error: danger,
        onPrimary: Colors.white,
        onSurface: darkTextPrimary,
        onSecondary: Colors.white,
        outline: darkCardBorder,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme.copyWith(
          headlineLarge: const TextStyle(fontWeight: FontWeight.w700, color: darkTextPrimary),
          headlineMedium: const TextStyle(fontWeight: FontWeight.w600, color: darkTextPrimary),
          titleLarge: const TextStyle(fontWeight: FontWeight.w600, color: darkTextPrimary),
          titleMedium: const TextStyle(fontWeight: FontWeight.w500, color: darkTextPrimary),
          bodyLarge: const TextStyle(color: darkTextPrimary),
          bodyMedium: const TextStyle(color: darkTextSecondary),
          bodySmall: const TextStyle(color: darkTextTertiary),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600, color: darkTextPrimary),
          labelMedium: const TextStyle(color: darkTextSecondary),
          labelSmall: const TextStyle(color: darkTextTertiary, fontSize: 11),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkCardBorder, width: 0.5),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: darkTextSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkCard,
        contentTextStyle: const TextStyle(color: darkTextPrimary, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkCardBorder,
        thickness: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: primary.withOpacity(0.12),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary);
          }
          return const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: darkTextTertiary);
        }),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: primaryDark,
      colorScheme: const ColorScheme.light(
        primary: primaryDark,
        secondary: accent,
        surface: lightSurface,
        error: danger,
        onPrimary: Colors.white,
        onSurface: lightTextPrimary,
        onSecondary: Colors.white,
        outline: lightCardBorder,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme.copyWith(
          headlineLarge: const TextStyle(fontWeight: FontWeight.w700, color: lightTextPrimary),
          headlineMedium: const TextStyle(fontWeight: FontWeight.w600, color: lightTextPrimary),
          titleLarge: const TextStyle(fontWeight: FontWeight.w600, color: lightTextPrimary),
          titleMedium: const TextStyle(fontWeight: FontWeight.w500, color: lightTextPrimary),
          bodyLarge: const TextStyle(color: lightTextPrimary),
          bodyMedium: const TextStyle(color: lightTextSecondary),
          bodySmall: const TextStyle(color: lightTextTertiary),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600, color: lightTextPrimary),
          labelMedium: const TextStyle(color: lightTextSecondary),
          labelSmall: const TextStyle(color: lightTextTertiary, fontSize: 11),
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: lightCardBorder, width: 0.5),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: lightTextSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: lightCardBorder,
        thickness: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface,
        indicatorColor: primaryDark.withOpacity(0.10),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryDark);
          }
          return const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: lightTextTertiary);
        }),
      ),
    );
  }
}
