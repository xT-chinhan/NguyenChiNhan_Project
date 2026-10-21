import 'package:flutter/material.dart';

/// Token màu theo mockup (design/mockup/styles.css). Màu chỉ mang nghĩa.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background, surface, container, containerHigh, outline, outlineVariant;
  final Color ink, muted, faint, primary, onPrimary;
  final Color income, successContainer, warning, warningContainer, warningBar, danger, dangerContainer, dangerBar;

  const AppColors({
    required this.background,
    required this.surface,
    required this.container,
    required this.containerHigh,
    required this.outline,
    required this.outlineVariant,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.primary,
    required this.onPrimary,
    required this.income,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.warningBar,
    required this.danger,
    required this.dangerContainer,
    required this.dangerBar,
  });

  static const light = AppColors(
    background: Color(0xFFF7F6F3),
    surface: Color(0xFFFFFFFF),
    container: Color(0xFFF1F0EC),
    containerHigh: Color(0xFFE9E8E3),
    outline: Color(0xFFEAEAEA),
    outlineVariant: Color(0xFFF0EFEC),
    ink: Color(0xFF111111),
    muted: Color(0xFF787774),
    faint: Color(0xFFA9A8A3),
    primary: Color(0xFF111111),
    onPrimary: Color(0xFFFFFFFF),
    income: Color(0xFF1F8A4C),
    successContainer: Color(0xFFEDF3EC),
    warning: Color(0xFF956400),
    warningContainer: Color(0xFFFBF3DB),
    warningBar: Color(0xFFD99A1E),
    danger: Color(0xFFB3261E),
    dangerContainer: Color(0xFFFDEBEC),
    dangerBar: Color(0xFFD9483B),
  );

  static const dark = AppColors(
    background: Color(0xFF121211),
    surface: Color(0xFF1C1C1A),
    container: Color(0xFF262624),
    containerHigh: Color(0xFF31312E),
    outline: Color(0xFF2E2E2B),
    outlineVariant: Color(0xFF262624),
    ink: Color(0xFFF2F1EE),
    muted: Color(0xFFA3A29D),
    faint: Color(0xFF6F6E69),
    primary: Color(0xFFF2F1EE),
    onPrimary: Color(0xFF111111),
    income: Color(0xFF5BC489),
    successContainer: Color(0xFF1D2B21),
    warning: Color(0xFFE8B54A),
    warningContainer: Color(0xFF2E2614),
    warningBar: Color(0xFFD99A1E),
    danger: Color(0xFFF2867D),
    dangerContainer: Color(0xFF3A1F1D),
    dangerBar: Color(0xFFD9483B),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < .5 ? this : (other as AppColors);
}

extension AppThemeX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  static ThemeData build(AppColors c, Brightness b) {
    // Be Vietnam Pro (dấu tiếng Việt chuẩn), nhúng sẵn trong assets/fonts
    final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: 'BeVietnamPro');
    final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink);
    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      colorScheme: ColorScheme.fromSeed(seedColor: c.primary, brightness: b).copyWith(
        primary: c.primary,
        onPrimary: c.onPrimary,
        surface: c.surface,
        onSurface: c.ink,
        error: c.danger,
      ),
      textTheme: text,
      extensions: [c],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textSelectionTheme: TextSelectionThemeData(cursorColor: c.ink, selectionColor: c.containerHigh, selectionHandleColor: c.ink),
      appBarTheme: AppBarTheme(backgroundColor: c.background, surfaceTintColor: Colors.transparent, elevation: 0, foregroundColor: c.ink),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: c.surface),
      dialogTheme: DialogThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
    );
  }

  static final light = build(AppColors.light, Brightness.light);
  static final dark = build(AppColors.dark, Brightness.dark);
}

/// Cỡ chữ theo tokens.md
class T {
  static const display = TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1.2, fontFeatures: [FontFeature.tabularFigures()]);
  static const headline = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.75, height: 1.25);
  static const titleL = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.3);
  static const titleM = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35);
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4);
  static const bodyM = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static const bodyS = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.45);
  static const label = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4);
  static const num = [FontFeature.tabularFigures()];
}
