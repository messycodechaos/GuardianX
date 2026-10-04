import 'package:flutter/material.dart';

class AppTheme {
  // Backgrounds: Deep Midnight Carbon & Slate
  static const Color background = Color(0xFF0B0F19);
  static const Color surface = Color(0xFF111827);
  static const Color card = Color(0xFF161F33);
  static const Color cardBorder = Color(0xFF222F49);

  // Primary Emergency & Tactical Accents
  static const Color crimson = Color(0xFFFF334B);
  static const Color crimsonGlow = Color(0x33FF334B);

  // Tactical Status Accents
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldGlow = Color(0x3310B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color azure = Color(0xFF3B82F6);
  static const Color violet = Color(0xFF8B5CF6);

  // Typography Colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: crimson,
      cardColor: card,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: crimson,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 10),
      ),
    );
  }
}