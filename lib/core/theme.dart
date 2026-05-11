import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Kneedle design system. Calm, warm, accessible — tuned for older users and
/// long-session readability on bright phone screens.
class KneedleTheme {
  KneedleTheme._();

  // ── Palette ────────────────────────────────────────────────────────────
  static const Color sage = Color(0xFF2E6F6A);
  static const Color sageDeep = Color(0xFF1F4F4A);
  static const Color sageTint = Color(0xFFE4EFEC);
  static const Color sageSoft = Color(0xFFF1F6F4);

  static const Color cream = Color(0xFFF6F2EA);
  static const Color creamWarm = Color(0xFFFBF8F1);
  static const Color surface = Colors.white;

  static const Color coral = Color(0xFFD97757);
  static const Color coralTint = Color(0xFFF7E5DC);
  static const Color amber = Color(0xFFE0A437);
  static const Color amberTint = Color(0xFFF8EBCE);

  static const Color ink = Color(0xFF14211F);
  static const Color inkMuted = Color(0xFF5D6B69);
  static const Color inkFaint = Color(0xFF8B9794);
  static const Color hairline = Color(0xFFEAE4D5);
  static const Color hairlineSoft = Color(0xFFF1ECDF);

  static const Color danger = Color(0xFFB1442D);
  static const Color dangerTint = Color(0xFFF7DDD3);
  static const Color success = Color(0xFF3F8C6B);
  static const Color successTint = Color(0xFFDDEDE3);

  // Back-compat aliases used elsewhere in the codebase.
  static const Color primary = sage;
  static const Color secondary = amber;
  static const Color background = cream;

  // ── Shape & spacing tokens ─────────────────────────────────────────────
  static const double radiusXs = 10;
  static const double radiusSm = 14;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 32;

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 32;
  static const double space8 = 40;

  static const List<BoxShadow> shadowSoft = [
    BoxShadow(
      color: Color(0x0F1A2826),
      blurRadius: 24,
      offset: Offset(0, 6),
      spreadRadius: -4,
    ),
  ];

  static const List<BoxShadow> shadowLifted = [
    BoxShadow(
      color: Color(0x141A2826),
      blurRadius: 32,
      offset: Offset(0, 12),
      spreadRadius: -6,
    ),
  ];

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: sage,
      onPrimary: Colors.white,
      primaryContainer: sageTint,
      onPrimaryContainer: sageDeep,
      secondary: coral,
      onSecondary: Colors.white,
      secondaryContainer: coralTint,
      onSecondaryContainer: Color(0xFF5E2E1A),
      tertiary: amber,
      onTertiary: Colors.white,
      tertiaryContainer: amberTint,
      onTertiaryContainer: Color(0xFF5C3F0F),
      error: danger,
      onError: Colors.white,
      errorContainer: dangerTint,
      onErrorContainer: Color(0xFF5F1F12),
      surface: surface,
      onSurface: ink,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: creamWarm,
      surfaceContainer: cream,
      surfaceContainerHigh: Color(0xFFF1ECDF),
      surfaceContainerHighest: Color(0xFFE9E3D2),
      onSurfaceVariant: inkMuted,
      outline: hairline,
      outlineVariant: hairlineSoft,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: ink,
      onInverseSurface: cream,
      inversePrimary: sageTint,
    );

    final base = ThemeData.light(useMaterial3: true);
    final text = _textTheme(base.textTheme);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      canvasColor: cream,
      dividerColor: hairlineSoft,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
          letterSpacing: -0.2,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: sage,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFC9D6D3),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: sageDeep,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: hairline, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: sageDeep,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      iconTheme: const IconThemeData(color: ink, size: 22),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: hairline, width: 1),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: sageSoft,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: sageDeep,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: sage, width: 1.6),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: sageDeep,
        textColor: ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: hairlineSoft,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: sage,
        linearTrackColor: hairlineSoft,
        circularTrackColor: hairlineSoft,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: sageTint,
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? sageDeep : inkMuted,
            letterSpacing: 0.1,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? sageDeep : inkMuted,
            size: 24,
          );
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: sage,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: inkMuted,
        indicatorColor: sage,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: hairline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    const display = TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      height: 1.1,
      color: ink,
    );
    return base
        .copyWith(
          displayLarge: display,
          displayMedium: display.copyWith(fontSize: 30, letterSpacing: -0.6),
          displaySmall: display.copyWith(fontSize: 26, letterSpacing: -0.5),
          headlineMedium: display.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          headlineSmall: display.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: ink,
            height: 1.25,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: ink,
            height: 1.3,
          ),
          titleSmall: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ink,
            height: 1.3,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: ink,
            fontWeight: FontWeight.w400,
          ),
          bodyMedium: const TextStyle(
            fontSize: 15,
            height: 1.45,
            color: inkMuted,
            fontWeight: FontWeight.w400,
          ),
          bodySmall: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: inkMuted,
            fontWeight: FontWeight.w400,
          ),
          labelLarge: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: inkMuted,
          ),
          labelMedium: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: inkMuted,
          ),
          labelSmall: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: inkFaint,
          ),
        )
        .apply(bodyColor: ink, displayColor: ink);
  }
}
