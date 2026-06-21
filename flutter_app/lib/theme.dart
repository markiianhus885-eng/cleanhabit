import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CleanHouse design tokens, taken from the "Clean modern app" redesign mockup.
/// Exposed as a [ThemeExtension] so widgets pull the right value for the
/// active brightness via `Theme.of(context).extension<ChColors>()!`.
@immutable
class ChColors extends ThemeExtension<ChColors> {
  final Color pageBg; // outer page background
  final Color card; // raised card surface
  final Color accent; // fresh green
  final Color textPrimary;
  final Color textSecondary; // muted labels
  final Color textFaint; // very muted / metadata
  final Color successPillBg; // green tinted chip background
  final Color successPillText;
  final Color divider;
  final Color navBar;
  final Color trackBg; // progress track / empty ring
  final Color star; // difficulty bolt
  final Color coinA; // coin gradient start
  final Color coinB; // coin gradient end

  const ChColors({
    required this.pageBg,
    required this.card,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.successPillBg,
    required this.successPillText,
    required this.divider,
    required this.navBar,
    required this.trackBg,
    required this.star,
    required this.coinA,
    required this.coinB,
  });

  static const light = ChColors(
    pageBg: Color(0xFFF4F7F4),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF15A05E),
    textPrimary: Color(0xFF1B2620),
    textSecondary: Color(0xFF73807A),
    textFaint: Color(0xFF9AA8A1),
    successPillBg: Color(0xFFEEF6F0),
    successPillText: Color(0xFF0C6B3E),
    divider: Color(0xFFEEF1EE),
    navBar: Color(0xFFFFFFFF),
    trackBg: Color(0xFFE7EEEA),
    star: Color(0xFFE0A93B),
    coinA: Color(0xFFF6CE72),
    coinB: Color(0xFFD99A2B),
  );

  static const dark = ChColors(
    pageBg: Color(0xFF0E1411),
    card: Color(0xFF18211D),
    accent: Color(0xFF35D07F),
    textPrimary: Color(0xFFECF3EF),
    textSecondary: Color(0xFF93A39B),
    textFaint: Color(0xFF6E7E76),
    successPillBg: Color(0xFF15271D),
    successPillText: Color(0xFF6FE0A6),
    divider: Color(0x14FFFFFF),
    navBar: Color(0xFF131A16),
    trackBg: Color(0xFF243029),
    star: Color(0xFFE0A93B),
    coinA: Color(0xFFF6CE72),
    coinB: Color(0xFFD99A2B),
  );

  @override
  ChColors copyWith({
    Color? pageBg,
    Color? card,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textFaint,
    Color? successPillBg,
    Color? successPillText,
    Color? divider,
    Color? navBar,
    Color? trackBg,
    Color? star,
    Color? coinA,
    Color? coinB,
  }) {
    return ChColors(
      pageBg: pageBg ?? this.pageBg,
      card: card ?? this.card,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textFaint: textFaint ?? this.textFaint,
      successPillBg: successPillBg ?? this.successPillBg,
      successPillText: successPillText ?? this.successPillText,
      divider: divider ?? this.divider,
      navBar: navBar ?? this.navBar,
      trackBg: trackBg ?? this.trackBg,
      star: star ?? this.star,
      coinA: coinA ?? this.coinA,
      coinB: coinB ?? this.coinB,
    );
  }

  @override
  ChColors lerp(ThemeExtension<ChColors>? other, double t) {
    if (other is! ChColors) return this;
    return ChColors(
      pageBg: Color.lerp(pageBg, other.pageBg, t)!,
      card: Color.lerp(card, other.card, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      successPillBg: Color.lerp(successPillBg, other.successPillBg, t)!,
      successPillText: Color.lerp(successPillText, other.successPillText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      trackBg: Color.lerp(trackBg, other.trackBg, t)!,
      star: Color.lerp(star, other.star, t)!,
      coinA: Color.lerp(coinA, other.coinA, t)!,
      coinB: Color.lerp(coinB, other.coinB, t)!,
    );
  }
}

/// Convenience accessor: `context.ch`
extension ChContext on BuildContext {
  ChColors get ch => Theme.of(this).extension<ChColors>()!;
}

ThemeData _build(ChColors c, Brightness brightness, String lang) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  // Plus Jakarta Sans has no Cyrillic, so Ukrainian uses Manrope (full
  // Latin + Cyrillic-ext incl. і/є/ї/ґ). Polish (Latin-ext) renders fine in
  // Plus Jakarta Sans. Noto Sans is the missing-glyph fallback either way.
  final TextTheme fontTheme = lang == 'uk'
      ? GoogleFonts.manropeTextTheme(base.textTheme)
      : GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
  final fallback = [GoogleFonts.notoSans().fontFamily!];
  final textTheme = fontTheme
      .apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
        fontFamilyFallback: fallback,
      );
  return base.copyWith(
    scaffoldBackgroundColor: c.pageBg,
    canvasColor: c.pageBg,
    colorScheme: base.colorScheme.copyWith(
      primary: c.accent,
      secondary: c.accent,
      surface: c.card,
      brightness: brightness,
    ),
    textTheme: textTheme,
    dividerColor: c.divider,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
  );
}

ThemeData buildLightTheme(String lang) =>
    _build(ChColors.light, Brightness.light, lang);
ThemeData buildDarkTheme(String lang) =>
    _build(ChColors.dark, Brightness.dark, lang);
