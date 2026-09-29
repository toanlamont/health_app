import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _primary = Color(0xFF0E9888);

/// One colour per measurement, used everywhere that measurement appears.
///
/// The screens used to mix `colorScheme.error`, `colorScheme.primary` and a
/// hard-coded `Colors.orange` in the same row, so a card's colour said nothing
/// about what was on it and changing the theme broke half of them. Here the
/// colour is the label: red is always the pulse, orange is always food.
class Metric {
  const Metric._();

  static const heart = Color(0xFFE5484D);
  static const calories = Color(0xFFF76808);
  static const weight = Color(0xFF8E4EC6);
  static const goal = Color(0xFF0E9888);
  static const reminder = Color(0xFF3E63DD);

  /// A soft wash of [colour] for card backgrounds, readable in both themes.
  static List<Color> wash(Color colour, Brightness brightness) =>
      brightness == Brightness.dark
      ? [
          Color.alphaBlend(colour.withValues(alpha: 0.22), const Color(0xFF15181C)),
          Color.alphaBlend(colour.withValues(alpha: 0.08), const Color(0xFF15181C)),
        ]
      : [
          Color.alphaBlend(colour.withValues(alpha: 0.16), Colors.white),
          Color.alphaBlend(colour.withValues(alpha: 0.04), Colors.white),
        ];
}

ThemeData _build(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: brightness,
    primary: dark ? const Color(0xFF3DBFA8) : _primary,
    error: Metric.heart,
  );
  final base = dark ? ThemeData.dark() : ThemeData.light();

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0F1214)
        : const Color(0xFFF7F8F9),
    textTheme: GoogleFonts.nunitoSansTextTheme(base.textTheme).copyWith(
      // The measurements are the point of the app, so the sizes that show them
      // are tightened up and weighted rather than left at the defaults.
      displayMedium: GoogleFonts.nunitoSans(
        fontSize: 52,
        fontWeight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -1.5,
      ),
      displaySmall: GoogleFonts.nunitoSans(
        fontSize: 38,
        fontWeight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -1,
      ),
      headlineSmall: GoogleFonts.nunitoSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.nunitoSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.nunitoSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF181C1F) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.nunitoSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF181C1F) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF15181C) : Colors.white,
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.nunitoSans(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide.none,
    ),
  );
}

final lightTheme = _build(Brightness.light);
final darkTheme = _build(Brightness.dark);
