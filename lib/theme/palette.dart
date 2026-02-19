import 'package:flutter/material.dart';

enum AccentPalette {
  green,
  blue,
  orange,
  red,
  teal,
  violet,
  amber,
  rose,
  cyan,
  indigo,
  copper,
  slateBlue,
  forest,
  coral,
  royal,
  graphite,
  magenta,
  sunset,
}

class AccentPaletteColors {
  const AccentPaletteColors({
    required this.primary,
    required this.secondary,
    required this.accent,
  });

  final Color primary;
  final Color secondary;
  final Color accent;
}

class AppPalette {
  static const Color ink = Color(0xFF0E1217);
  static const Color inkSoft = Color(0xFF1A202C);
  static const Color slate = Color(0xFF2B3240);
  static const Color mist = Color(0xFFF4F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F3F6);
  static const Color outline = Color(0xFFE0E5EC);

  static const Map<AccentPalette, AccentPaletteColors> _paletteSets = {
    AccentPalette.green: AccentPaletteColors(
      primary: Color(0xFF1FA97A),
      secondary: Color(0xFF4C7DFF),
      accent: Color(0xFFFF8A5B),
    ),
    AccentPalette.blue: AccentPaletteColors(
      primary: Color(0xFF2D7FF9),
      secondary: Color(0xFF00A6ED),
      accent: Color(0xFF5E60CE),
    ),
    AccentPalette.orange: AccentPaletteColors(
      primary: Color(0xFFF08A24),
      secondary: Color(0xFFFFB347),
      accent: Color(0xFFE4572E),
    ),
    AccentPalette.red: AccentPaletteColors(
      primary: Color(0xFFD64045),
      secondary: Color(0xFFFB5607),
      accent: Color(0xFFB5179E),
    ),
    AccentPalette.teal: AccentPaletteColors(
      primary: Color(0xFF0FA3B1),
      secondary: Color(0xFF3DCCC7),
      accent: Color(0xFF2A9D8F),
    ),
    AccentPalette.violet: AccentPaletteColors(
      primary: Color(0xFF6C63FF),
      secondary: Color(0xFF8E7CFF),
      accent: Color(0xFFB388EB),
    ),
    AccentPalette.amber: AccentPaletteColors(
      primary: Color(0xFFF59F00),
      secondary: Color(0xFFFAB005),
      accent: Color(0xFFFFC078),
    ),
    AccentPalette.rose: AccentPaletteColors(
      primary: Color(0xFFE64980),
      secondary: Color(0xFFFF6B9A),
      accent: Color(0xFFFF8787),
    ),
    AccentPalette.cyan: AccentPaletteColors(
      primary: Color(0xFF00A8B5),
      secondary: Color(0xFF00C2D1),
      accent: Color(0xFF48CAE4),
    ),
    AccentPalette.indigo: AccentPaletteColors(
      primary: Color(0xFF3A56D4),
      secondary: Color(0xFF5C7CFA),
      accent: Color(0xFF748FFC),
    ),
    AccentPalette.copper: AccentPaletteColors(
      primary: Color(0xFFB5654A),
      secondary: Color(0xFFD17A5A),
      accent: Color(0xFFE9A178),
    ),
    AccentPalette.slateBlue: AccentPaletteColors(
      primary: Color(0xFF4B6281),
      secondary: Color(0xFF6C84A3),
      accent: Color(0xFF88A0BF),
    ),
    AccentPalette.forest: AccentPaletteColors(
      primary: Color(0xFF1B7F5B),
      secondary: Color(0xFF2FA57C),
      accent: Color(0xFF7ACB9F),
    ),
    AccentPalette.coral: AccentPaletteColors(
      primary: Color(0xFFE76F51),
      secondary: Color(0xFFF4A261),
      accent: Color(0xFFEAAC8B),
    ),
    AccentPalette.royal: AccentPaletteColors(
      primary: Color(0xFF274690),
      secondary: Color(0xFF576CA8),
      accent: Color(0xFF8EA8FF),
    ),
    AccentPalette.graphite: AccentPaletteColors(
      primary: Color(0xFF495057),
      secondary: Color(0xFF6C757D),
      accent: Color(0xFFADB5BD),
    ),
    AccentPalette.magenta: AccentPaletteColors(
      primary: Color(0xFFB5179E),
      secondary: Color(0xFFD63384),
      accent: Color(0xFFFF4D9A),
    ),
    AccentPalette.sunset: AccentPaletteColors(
      primary: Color(0xFFEF476F),
      secondary: Color(0xFFFF8A5B),
      accent: Color(0xFFFFC971),
    ),
  };

  static AccentPalette _activePalette = AccentPalette.blue;
  static AccentPaletteColors _activeColors = _paletteSets[_activePalette]!;

  static AccentPalette get activePalette => _activePalette;
  static Color get primary => _activeColors.primary;
  static Color get secondary => _activeColors.secondary;
  static Color get accent => _activeColors.accent;

  static const Color success = Color(0xFF2AC769);
  static const Color warning = Color(0xFFF2C94C);
  static const Color danger = Color(0xFFE04F5F);

  static void applyPalette(AccentPalette palette) {
    _activePalette = palette;
    _activeColors = _paletteSets[palette] ?? _paletteSets[AccentPalette.blue]!;
  }

  static AccentPalette paletteFromName(String? value) {
    return switch (value) {
      'green' => AccentPalette.green,
      'orange' => AccentPalette.orange,
      'red' => AccentPalette.red,
      'teal' => AccentPalette.teal,
      'violet' => AccentPalette.violet,
      'amber' => AccentPalette.amber,
      'rose' => AccentPalette.rose,
      'cyan' => AccentPalette.cyan,
      'indigo' => AccentPalette.indigo,
      'copper' => AccentPalette.copper,
      'slateBlue' => AccentPalette.slateBlue,
      'forest' => AccentPalette.forest,
      'coral' => AccentPalette.coral,
      'royal' => AccentPalette.royal,
      'graphite' => AccentPalette.graphite,
      'magenta' => AccentPalette.magenta,
      'sunset' => AccentPalette.sunset,
      _ => AccentPalette.blue,
    };
  }

  static String paletteName(AccentPalette palette) {
    return switch (palette) {
      AccentPalette.green => 'green',
      AccentPalette.blue => 'blue',
      AccentPalette.orange => 'orange',
      AccentPalette.red => 'red',
      AccentPalette.teal => 'teal',
      AccentPalette.violet => 'violet',
      AccentPalette.amber => 'amber',
      AccentPalette.rose => 'rose',
      AccentPalette.cyan => 'cyan',
      AccentPalette.indigo => 'indigo',
      AccentPalette.copper => 'copper',
      AccentPalette.slateBlue => 'slateBlue',
      AccentPalette.forest => 'forest',
      AccentPalette.coral => 'coral',
      AccentPalette.royal => 'royal',
      AccentPalette.graphite => 'graphite',
      AccentPalette.magenta => 'magenta',
      AccentPalette.sunset => 'sunset',
    };
  }

  static String paletteLabel(AccentPalette palette) {
    return switch (palette) {
      AccentPalette.green => 'Green',
      AccentPalette.blue => 'Blue',
      AccentPalette.orange => 'Orange',
      AccentPalette.red => 'Red',
      AccentPalette.teal => 'Teal',
      AccentPalette.violet => 'Violet',
      AccentPalette.amber => 'Amber',
      AccentPalette.rose => 'Rose',
      AccentPalette.cyan => 'Cyan',
      AccentPalette.indigo => 'Indigo',
      AccentPalette.copper => 'Copper',
      AccentPalette.slateBlue => 'Slate Blue',
      AccentPalette.forest => 'Forest',
      AccentPalette.coral => 'Coral',
      AccentPalette.royal => 'Royal',
      AccentPalette.graphite => 'Graphite',
      AccentPalette.magenta => 'Magenta',
      AccentPalette.sunset => 'Sunset',
    };
  }
}
