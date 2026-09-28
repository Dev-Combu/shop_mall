import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 시각적 색상 체계 (Theme System)
class AppTheme {
  // 1. 주요 색상 (Primary Color) - 신뢰감을 주는 모던 딥 찰콜/네이비
  static const Color primary = Color(0xFF1E293B);
  static const Color primaryDark = Color(0xFF0F172A);

  // 2. 포인트 색상 (Point / Accent Color) - 중요한 강조, 할인율, 구매 버튼에만 절제하여 사용하는 브라이트 레드
  static const Color point = Color(0xFFE53935);
  static const Color pointLight = Color(0xFFFFEBEE);

  // 3. 반전 / 보조 배경 색상 (Surface / Background Contrast) - 눈이 편안한 소프트 크림 & 쿨그레이
  static const Color background = Color(0xFFF8FAFC);  // 매끄럽고 은은한 전체 배경
  static const Color surface = Color(0xFFFFFFFF);     // 카드 및 섹션 하얀색 배경
  static const Color chipBackground = Color(0xFFF1F5F9); // 칩/태그용 연한 회색/블루 틴트
  static const Color border = Color(0xFFE2E8F0);       // 은은한 구분선/테두리

  // 4. 상태 및 보조 포인트 (Sub Accent) - 배송/안내/성공에 사용되는 소프트 그린 & 블루
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFECFDF5);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFEFF6FF);

  static final ThemeData lightTheme = ThemeData(
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    useMaterial3: true,
    fontFamily: 'Pretendard',
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: point,
      surface: surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFF1E293B),
    ),

    // App Bar 테마: 눈이 편안한 깔끔한 화이트 + 딥 찰콜 텍스트
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: primary,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),

    // 입력창 테마: 차분하고 부드러운 필드
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
    ),

    // 버튼 테마: 주요 행동 버튼은 포인트 컬러(레드) 또는 메인 컬러(딥 찰콜)로 적용
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: point,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    // 체크박스 & 스위치
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return point;
        }
        return null;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return point;
        }
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return pointLight;
        }
        return null;
      }),
    ),
  );
}