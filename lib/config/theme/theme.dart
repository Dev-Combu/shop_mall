import 'package:flutter/material.dart';

class AppTheme {
   static final ThemeData lightTheme = ThemeData(
    primaryColor: const Color.fromARGB(255, 255, 31, 31), // Deep purple
    scaffoldBackgroundColor: const Color(0xFFF9F6F0), // Warm beige
    useMaterial3: true,
    fontFamily: 'Pretendard', // Assuming a clean font, can be omitted if not imported
    colorScheme: ColorScheme.light(
      primary: const Color(0xFF6C63FF), // Deep purple
      onPrimary: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF212121), // Dark gray for text/icons
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    );
}