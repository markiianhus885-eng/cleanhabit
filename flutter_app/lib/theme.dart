import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CleanHouse design tokens — "Playful" gamified redesign.
/// Light-first purple/indigo palette with a dark variant. Exposed as a
/// [ThemeExtension] so widgets pull the right value for the active brightness
/// via `context.ch`.
@immutable
class ChColors extends ThemeExtension<ChColors> {
  final Color pageBg; // outer page background
  final Color card; // raised card surface
  final Color accent; // primary indigo
  final Color accentGradA; // hero gradient start
  final Color accentGradB; // hero gradient end
  final Color onAccent; // text/icon on accent surfaces
  final Color textPrimary;
  final Color textSecondary; // muted labels
  final Color textFaint; // very muted / metadata
  final Color successPillBg; // green tinted chip background
  final Color successPillText;
  final Color divider;
  final Color navBar;
  final Color trackBg; // progress track / empty ring
  final Color star; // xp / accent gold
  final Color coinA; // coin gradient start
  final Color coinB; // coin gradient end
  final Color flame; // streak flame
  final Color levelA; // xp bar gradient start (gold)
  final Color levelB; // xp bar gradient end (gold)
  final Color quickBg; // ⚡ quick tag bg
  final Color quickFg;
  final Color epicBg; // 🔥 epic tag bg
  final Color epicFg;
  final Color iconTint; // soft tile behind a quest icon

  const ChColors({
    required this.pageBg,
    required this.card,
    required this.accent,
    required this.accentGradA,
    required this.accentGradB,
    required this.onAccent,
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
    required this.flame,
    required this.levelA,
    required this.levelB,
    required this.quickBg,
    required this.quickFg,
    required this.epicBg,
    required this.epicFg,
    required this.iconTint,
  });

  /// Gradient used by the level/XP hero, daily-goal banner and the FAB.
  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accentGradA, accentGradB],
      );

  /// Gold XP fill for the level progress bar.
  LinearGradient get xpGradient => LinearGradient(
        colors: [levelA, levelB],
      );

  static const light = ChColors(
    pageBg: Color(0xFFF4F2FC),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF5563D8),
    accentGradA: Color(0xFF6D7BE6),
    accentGradB: Color(0xFF5159D6),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF2B2840),
    textSecondary: Color(0xFF908AA8),
    textFaint: Color(0xFFB0AAC8),
    successPillBg: Color(0xFFE6F6EE),
    successPillText: Color(0xFF2F8B5E),
    divider: Color(0xFFECE9F7),
    navBar: Color(0xFFFFFFFF),
    trackBg: Color(0xFFE6E1F4),
    star: Color(0xFFC98A00),
    coinA: Color(0xFFFFE08A),
    coinB: Color(0xFFE5A623),
    flame: Color(0xFFFF7A3D),
    levelA: Color(0xFFFFE08A),
    levelB: Color(0xFFFFC53D),
    quickBg: Color(0xFFEDE8FB),
    quickFg: Color(0xFF6354C4),
    epicBg: Color(0xFFFFE6EE),
    epicFg: Color(0xFFE5557A),
    iconTint: Color(0xFFF1ECFF),
  );

  static const dark = ChColors(
    pageBg: Color(0xFF191527),
    card: Color(0xFF241D33),
    accent: Color(0xFF8E97F2),
    accentGradA: Color(0xFF6D7BE6),
    accentGradB: Color(0xFF5159D6),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFECE8FA),
    textSecondary: Color(0xFF9A92B8),
    textFaint: Color(0xFF6F6890),
    successPillBg: Color(0xFF15291F),
    successPillText: Color(0xFF6FE0A6),
    divider: Color(0x14FFFFFF),
    navBar: Color(0xFF241D33),
    trackBg: Color(0xFF332A4A),
    star: Color(0xFFFFD86B),
    coinA: Color(0xFFFFE08A),
    coinB: Color(0xFFE5A623),
    flame: Color(0xFFFF7A3D),
    levelA: Color(0xFFFFE08A),
    levelB: Color(0xFFFFC53D),
    quickBg: Color(0xFF2E2650),
    quickFg: Color(0xFFB9AEF5),
    epicBg: Color(0xFF3A2138),
    epicFg: Color(0xFFF08AAB),
    iconTint: Color(0xFF2A2240),
  );

  @override
  ChColors copyWith({
    Color? pageBg,
    Color? card,
    Color? accent,
    Color? accentGradA,
    Color? accentGradB,
    Color? onAccent,
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
    Color? flame,
    Color? levelA,
    Color? levelB,
    Color? quickBg,
    Color? quickFg,
    Color? epicBg,
    Color? epicFg,
    Color? iconTint,
  }) {
    return ChColors(
      pageBg: pageBg ?? this.pageBg,
      card: card ?? this.card,
      accent: accent ?? this.accent,
      accentGradA: accentGradA ?? this.accentGradA,
      accentGradB: accentGradB ?? this.accentGradB,
      onAccent: onAccent ?? this.onAccent,
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
      flame: flame ?? this.flame,
      levelA: levelA ?? this.levelA,
      levelB: levelB ?? this.levelB,
      quickBg: quickBg ?? this.quickBg,
      quickFg: quickFg ?? this.quickFg,
      epicBg: epicBg ?? this.epicBg,
      epicFg: epicFg ?? this.epicFg,
      iconTint: iconTint ?? this.iconTint,
    );
  }

  @override
  ChColors lerp(ThemeExtension<ChColors>? other, double t) {
    if (other is! ChColors) return this;
    return ChColors(
      pageBg: Color.lerp(pageBg, other.pageBg, t)!,
      card: Color.lerp(card, other.card, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentGradA: Color.lerp(accentGradA, other.accentGradA, t)!,
      accentGradB: Color.lerp(accentGradB, other.accentGradB, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
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
      flame: Color.lerp(flame, other.flame, t)!,
      levelA: Color.lerp(levelA, other.levelA, t)!,
      levelB: Color.lerp(levelB, other.levelB, t)!,
      quickBg: Color.lerp(quickBg, other.quickBg, t)!,
      quickFg: Color.lerp(quickFg, other.quickFg, t)!,
      epicBg: Color.lerp(epicBg, other.epicBg, t)!,
      epicFg: Color.lerp(epicFg, other.epicFg, t)!,
      iconTint: Color.lerp(iconTint, other.iconTint, t)!,
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
  // Strip any inherited TextDecoration (Google Fonts / Material3 can leave
  // underline decorations on some styles that render as yellow bars on screen).
  TextTheme _stripDeco(TextTheme t) {
    TextStyle strip(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(decoration: TextDecoration.none, decorationColor: Colors.transparent);
    return t.copyWith(
      displayLarge: strip(t.displayLarge), displayMedium: strip(t.displayMedium),
      displaySmall: strip(t.displaySmall), headlineLarge: strip(t.headlineLarge),
      headlineMedium: strip(t.headlineMedium), headlineSmall: strip(t.headlineSmall),
      titleLarge: strip(t.titleLarge), titleMedium: strip(t.titleMedium),
      titleSmall: strip(t.titleSmall), bodyLarge: strip(t.bodyLarge),
      bodyMedium: strip(t.bodyMedium), bodySmall: strip(t.bodySmall),
      labelLarge: strip(t.labelLarge), labelMedium: strip(t.labelMedium),
      labelSmall: strip(t.labelSmall),
    );
  }
  final textTheme = _stripDeco(fontTheme.apply(
    bodyColor: c.textPrimary,
    displayColor: c.textPrimary,
    fontFamilyFallback: fallback,
  ));
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
    primaryTextTheme: textTheme,
    dividerColor: c.divider,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
  );
}

ThemeData buildLightTheme(String lang) =>
    _build(ChColors.light, Brightness.light, lang);
ThemeData buildDarkTheme(String lang) =>
    _build(ChColors.dark, Brightness.dark, lang);
