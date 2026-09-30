import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tokens.g.dart';

export 'tokens.g.dart';

/// The design tokens of the current theme, for what Material's
/// [ColorScheme] has no slot for: cue colours, stage colours, glass.
class SaTheme extends ThemeExtension<SaTheme> {
  const SaTheme(this.palette);

  final SaPalette palette;

  /// The palette of the nearest theme (Studio light or Studio dark).
  static SaPalette of(BuildContext context) => Theme.of(context).extension<SaTheme>()?.palette ?? SaPalette.light;

  @override
  SaTheme copyWith({SaPalette? palette}) => SaTheme(palette ?? this.palette);

  @override
  SaTheme lerp(SaTheme? other, double t) => t < 0.5 || other == null ? this : other;
}

/// A text style at a width of its font's width axis (Anybody: 50 to 150;
/// Martian Mono: 75 to 112.5). The display voice uses width to show pace:
/// wide is slow, narrow is fast.
///
/// Setting any variation replaces Flutter's automatic weight mapping, so
/// the weight is set explicitly too.
TextStyle atWidth(TextStyle style, double width) => style.copyWith(fontVariations: [
      ui.FontVariation('wght', (style.fontWeight ?? FontWeight.w400).value.toDouble()),
      ui.FontVariation('wdth', width),
    ]);

/// The Studio theme for [brightness], built from the design tokens.
ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? SaPalette.dark : SaPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.surfaceSunk,
    onPrimaryContainer: p.ink,
    secondary: p.cue,
    onSecondary: p.onCue,
    secondaryContainer: p.surfaceSunk,
    onSecondaryContainer: p.ink,
    tertiary: p.cuePause,
    onTertiary: p.onPrimary,
    error: p.danger,
    onError: p.onPrimary,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.ink2,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surface,
    surfaceContainerHighest: p.surfaceSunk,
    surfaceTint: Colors.transparent,
    outline: p.lineStrong,
    outlineVariant: p.line,
    shadow: Colors.black,
    scrim: p.stageScrim,
    inverseSurface: p.ink,
    onInverseSurface: p.paper,
    inversePrimary: p.cue,
  );

  TextStyle ink(TextStyle s, [Color? color]) => s.copyWith(color: color ?? p.ink);
  final display = atWidth(SaType.display, 112);
  final text = TextTheme(
    displayLarge: ink(display),
    displayMedium: ink(display),
    displaySmall: ink(display),
    headlineLarge: ink(SaType.titleLg),
    headlineMedium: ink(SaType.titleLg),
    headlineSmall: ink(SaType.titleLg),
    titleLarge: ink(SaType.title),
    titleMedium: ink(SaType.body.copyWith(fontWeight: FontWeight.w600)),
    titleSmall: ink(SaType.bodySm.copyWith(fontWeight: FontWeight.w600)),
    bodyLarge: ink(SaType.body),
    bodyMedium: ink(SaType.bodySm),
    bodySmall: ink(SaType.caption, p.ink3),
    labelLarge: ink(SaType.label),
    labelMedium: ink(SaType.label.copyWith(fontSize: 12)),
    labelSmall: ink(SaType.caption.copyWith(fontWeight: FontWeight.w600), p.ink2),
  );

  final radiusMd = BorderRadius.circular(SaRadius.md);
  final buttonShape = WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusMd));
  const buttonSize = WidgetStatePropertyAll(Size(40, 40));
  final labelStyle = WidgetStatePropertyAll(SaType.label);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: SaFonts.reading,
    textTheme: text,
    scaffoldBackgroundColor: p.paper,
    canvasColor: p.paper,
    dividerColor: p.line,
    focusColor: p.tintSelect,
    hoverColor: p.ink.withValues(alpha: 0.04),
    splashFactory: InkRipple.splashFactory,
    extensions: [SaTheme(p)],
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: ink(SaType.title),
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radiusMd, side: BorderSide(color: p.line)),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? p.primary.withValues(alpha: 0.38) : p.primary),
        foregroundColor: WidgetStatePropertyAll(p.onPrimary),
        shape: buttonShape,
        minimumSize: buttonSize,
        textStyle: labelStyle,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: SaSpace.s4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(p.ink),
        side: WidgetStatePropertyAll(BorderSide(color: p.lineStrong)),
        shape: buttonShape,
        minimumSize: buttonSize,
        textStyle: labelStyle,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: SaSpace.s4)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(p.ink),
        shape: buttonShape,
        minimumSize: buttonSize,
        textStyle: labelStyle,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
      extendedTextStyle: SaType.label,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.surface : p.surfaceSunk),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : p.ink2),
        side: WidgetStatePropertyAll(BorderSide(color: p.line)),
        textStyle: labelStyle,
        shape: buttonShape,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.primary,
      side: BorderSide(color: p.lineStrong),
      labelStyle: ink(SaType.label),
      secondaryLabelStyle: SaType.label.copyWith(color: p.onPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SaRadius.sm)),
      checkmarkColor: p.onPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: p.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: p.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: p.focus, width: 2)),
      labelStyle: ink(SaType.bodySm, p.ink2),
      hintStyle: ink(SaType.body, p.ink3),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SaRadius.lg))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SaRadius.lg)),
      titleTextStyle: ink(SaType.title),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: SaType.bodySm.copyWith(color: p.paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onPrimary : p.surface),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.lineStrong),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: ink(SaType.body.copyWith(fontWeight: FontWeight.w600)),
      subtitleTextStyle: ink(SaType.bodySm, p.ink3),
      iconColor: p.ink2,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(SaRadius.sm)),
      textStyle: SaType.caption.copyWith(color: p.paper),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.ink, linearTrackColor: p.surfaceSunk),
  );
}
