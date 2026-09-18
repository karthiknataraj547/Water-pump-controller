import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Precision Industrial Color Palette
  static const Color primary = Color(0xFF0284C7);       // Electric Azure
  static const Color primaryLight = Color(0xFF38BDF8);  // Crisp Cyan-Sky
  static const Color primaryDark = Color(0xFF0369A1);   // Deep Industrial Cobalt
  static const Color accent = Color(0xFF10B981);        // Industrial Emerald (Running / Normal)
  static const Color warning = Color(0xFFF59E0B);       // Industrial Amber (Caution / Threshold)
  static const Color danger = Color(0xFFEF4444);        // Safety Crimson (Trip / Interlock)
  static const Color dangerLight = Color(0xFFF87171);
  static const Color slate = Color(0xFF64748B);         // Inactive / Standby

  // Obsidian Dark Mode Surfaces (Deep Aerospace Slate, zero muddy purple)
  static const Color darkBg = Color(0xFF090D14);
  static const Color darkSurface = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF111827);
  static const Color darkCardBorder = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);

  // Studio Slate Light Mode Surfaces (Clean Architectural Neutrals)
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Water & Flow Telemetry Colors
  static const Color waterBlue = Color(0xFF38BDF8);
  static const Color waterBlueDark = Color(0xFF0284C7);
  static const Color waterBlueDarkMode = Color(0xFF0284C7);

  // Backward compatibility aliases
  static const Color primaryCyan = primaryLight;
  static const Color primaryBlue = primary;
  static const Color accentEmerald = accent;
  static const Color accentAmber = warning;
  static const Color accentRose = danger;

  static const LinearGradient hydroGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [accent, Color(0xFF059669)],
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
          headlineLarge: const TextStyle(fontWeight: FontWeight.w700, color: darkTextPrimary, letterSpacing: -0.5),
          headlineMedium: const TextStyle(fontWeight: FontWeight.w700, color: darkTextPrimary, letterSpacing: -0.3),
          titleLarge: const TextStyle(fontWeight: FontWeight.w700, color: darkTextPrimary, letterSpacing: -0.2),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600, color: darkTextPrimary),
          bodyLarge: const TextStyle(color: darkTextPrimary, fontSize: 15),
          bodyMedium: const TextStyle(color: darkTextSecondary, fontSize: 13.5),
          bodySmall: const TextStyle(color: darkTextTertiary, fontSize: 12),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600, color: darkTextPrimary, fontSize: 13),
          labelMedium: const TextStyle(fontWeight: FontWeight.w500, color: darkTextSecondary, fontSize: 12),
          labelSmall: const TextStyle(fontWeight: FontWeight.w700, color: darkTextTertiary, fontSize: 10.5, letterSpacing: 1.1),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkCardBorder, width: 0.8),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: darkTextSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0B111E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: darkTextTertiary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkCardBorder, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkCardBorder, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.0),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkCard,
        contentTextStyle: const TextStyle(color: darkTextPrimary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: darkCardBorder, width: 0.8)),
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkTextPrimary,
          side: const BorderSide(color: darkCardBorder, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkCardBorder,
        thickness: 0.8,
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
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
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
          headlineLarge: const TextStyle(fontWeight: FontWeight.w700, color: lightTextPrimary, letterSpacing: -0.5),
          headlineMedium: const TextStyle(fontWeight: FontWeight.w700, color: lightTextPrimary, letterSpacing: -0.3),
          titleLarge: const TextStyle(fontWeight: FontWeight.w700, color: lightTextPrimary, letterSpacing: -0.2),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600, color: lightTextPrimary),
          bodyLarge: const TextStyle(color: lightTextPrimary, fontSize: 15),
          bodyMedium: const TextStyle(color: lightTextSecondary, fontSize: 13.5),
          bodySmall: const TextStyle(color: lightTextTertiary, fontSize: 12),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600, color: lightTextPrimary, fontSize: 13),
          labelMedium: const TextStyle(fontWeight: FontWeight.w500, color: lightTextSecondary, fontSize: 12),
          labelSmall: const TextStyle(fontWeight: FontWeight.w700, color: lightTextTertiary, fontSize: 10.5, letterSpacing: 1.1),
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightCardBorder, width: 0.8),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: lightTextSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: lightTextTertiary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightCardBorder, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightCardBorder, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.0),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightTextPrimary,
          side: const BorderSide(color: lightCardBorder, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: lightCardBorder,
        thickness: 0.8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface,
        indicatorColor: primary.withOpacity(0.10),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary);
          }
          return const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: lightTextTertiary);
        }),
      ),
    );
  }
}
