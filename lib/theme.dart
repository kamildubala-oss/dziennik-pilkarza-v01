import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemePreference { light, dark, system }

/// Odstępy (spacing) - identyczne jak w wersji React.
class Sp {
  Sp._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Promienie zaokrągleń.
class Rad {
  Rad._();
  static const double sm = 6;
  static const double md = 12;
  static const double lg = 20;
  static const double pill = 999;
}

@immutable
class AppColors {
  const AppColors({
    required this.surface,
    required this.onSurface,
    required this.surfaceSecondary,
    required this.onSurfaceSecondary,
    required this.surfaceTertiary,
    required this.onSurfaceTertiary,
    required this.surfaceInverse,
    required this.onSurfaceInverse,
    required this.muted,
    required this.brand,
    required this.onBrand,
    required this.brandPrimary,
    required this.onBrandPrimary,
    required this.brandSecondary,
    required this.onBrandSecondary,
    required this.brandTertiary,
    required this.onBrandTertiary,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.error,
    required this.onError,
    required this.info,
    required this.onInfo,
    required this.border,
    required this.borderStrong,
    required this.divider,
  });

  final Color surface;
  final Color onSurface;
  final Color surfaceSecondary;
  final Color onSurfaceSecondary;
  final Color surfaceTertiary;
  final Color onSurfaceTertiary;
  final Color surfaceInverse;
  final Color onSurfaceInverse;
  final Color muted;
  final Color brand;
  final Color onBrand;
  final Color brandPrimary;
  final Color onBrandPrimary;
  final Color brandSecondary;
  final Color onBrandSecondary;
  final Color brandTertiary;
  final Color onBrandTertiary;
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color error;
  final Color onError;
  final Color info;
  final Color onInfo;
  final Color border;
  final Color borderStrong;
  final Color divider;

  // -------- Ciemny (domyślny, Volt Green) --------
  static const AppColors dark = AppColors(
    surface: Color(0xFF0F1115),
    onSurface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFF1A1D24),
    onSurfaceSecondary: Color(0xFFFFFFFF),
    surfaceTertiary: Color(0xFF252A33),
    onSurfaceTertiary: Color(0xFFFFFFFF),
    surfaceInverse: Color(0xFFFFFFFF),
    onSurfaceInverse: Color(0xFF0F1115),
    muted: Color(0xFF8E95A3),
    brand: Color(0xFFD4FF26),
    onBrand: Color(0xFF000000),
    brandPrimary: Color(0xFFD4FF26),
    onBrandPrimary: Color(0xFF000000),
    brandSecondary: Color(0xFFFF4D00),
    onBrandSecondary: Color(0xFFFFFFFF),
    brandTertiary: Color(0xFF333C1A),
    onBrandTertiary: Color(0xFFD4FF26),
    success: Color(0xFFD4FF26),
    onSuccess: Color(0xFF000000),
    warning: Color(0xFFFFB017),
    onWarning: Color(0xFF000000),
    error: Color(0xFFFF3B30),
    onError: Color(0xFFFFFFFF),
    info: Color(0xFF252A33),
    onInfo: Color(0xFFFFFFFF),
    border: Color(0xFF2A2E37),
    borderStrong: Color(0xFF3F4552),
    divider: Color(0xFF1F232B),
  );

  // -------- Jasny --------
  static const AppColors light = AppColors(
    surface: Color(0xFFFAFAF7),
    onSurface: Color(0xFF0F1115),
    surfaceSecondary: Color(0xFFFFFFFF),
    onSurfaceSecondary: Color(0xFF0F1115),
    surfaceTertiary: Color(0xFFF1F2EE),
    onSurfaceTertiary: Color(0xFF0F1115),
    surfaceInverse: Color(0xFF0F1115),
    onSurfaceInverse: Color(0xFFFFFFFF),
    muted: Color(0xFF6B7280),
    brand: Color(0xFF0F1115),
    onBrand: Color(0xFFFFFFFF),
    brandPrimary: Color(0xFF0F1115),
    onBrandPrimary: Color(0xFFFFFFFF),
    brandSecondary: Color(0xFFFF4D00),
    onBrandSecondary: Color(0xFFFFFFFF),
    brandTertiary: Color(0xFFD4FF26),
    onBrandTertiary: Color(0xFF0F1115),
    success: Color(0xFF15803D),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFFB45309),
    onWarning: Color(0xFFFFFFFF),
    error: Color(0xFFB91C1C),
    onError: Color(0xFFFFFFFF),
    info: Color(0xFFE5E7EB),
    onInfo: Color(0xFF0F1115),
    border: Color(0xFFE5E7EB),
    borderStrong: Color(0xFFD1D5DB),
    divider: Color(0xFFEAEBEE),
  );
}

/// Kolory aktualnego motywu: `context.c.brandPrimary` itd.
extension AppContext on BuildContext {
  AppColors get c => Theme.of(this).brightness == Brightness.light
      ? AppColors.light
      : AppColors.dark;
}

/// Manrope - tekst podstawowy.
TextStyle manrope({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Manrope',
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Barlow Condensed - nagłówki i duże liczby.
TextStyle barlow({
  double size = 14,
  FontWeight weight = FontWeight.w800,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'BarlowCondensed',
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

ThemeData buildTheme(AppColors c, Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: c.surface,
    canvasColor: c.surface,
    colorScheme: base.colorScheme.copyWith(
      primary: c.brandPrimary,
      onPrimary: c.onBrandPrimary,
      secondary: c.brandSecondary,
      onSecondary: c.onBrandSecondary,
      error: c.error,
      onError: c.onError,
      surface: c.surface,
      onSurface: c.onSurface,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Manrope',
      bodyColor: c.onSurface,
      displayColor: c.onSurface,
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: c.brandPrimary.withValues(alpha: 0.12),
    hoverColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.brandPrimary,
      selectionColor: c.brandPrimary.withAlpha(77),
      selectionHandleColor: c.brandPrimary,
    ),
  );
}

/// Preferencja motywu zapisywana lokalnie (jak `mp.themePreference`).
class ThemeController extends ChangeNotifier {
  static const String _key = 'mp.themePreference';

  ThemePreference _preference = ThemePreference.dark;
  ThemePreference get preference => _preference;

  ThemeMode get themeMode {
    switch (_preference) {
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
      case ThemePreference.system:
        return ThemeMode.system;
    }
  }

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.get(_key);
      for (final p in ThemePreference.values) {
        if (p.name == v) {
          if (_preference != p) {
            _preference = p;
            notifyListeners();
          }
          break;
        }
      }
    } catch (_) {
      // Brak dostępu do pamięci - zostaje motyw domyślny (ciemny).
    }
  }

  Future<void> setPreference(ThemePreference p) async {
    _preference = p;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, p.name);
    } catch (_) {
      // Zapis jest "best effort".
    }
  }
}

/// Kolor aktywności w kalendarzu (kropki, etykiety).
/// training - trening zawodnika, club_training - trening klubowy,
/// match - mecz, note - notatka.
Color eventTypeColor(AppColors c, String type) {
  switch (type) {
    case 'club_training':
      return const Color(0xFF3B82F6); // niebieski
    case 'match':
      return c.brandSecondary; // pomarańczowy
    case 'note':
      return const Color(0xFFA855F7); // fioletowy
    default:
      // Trening zawodnika: limonkowy (w jasnym motywie zielony).
      return c.brandPrimary == const Color(0xFFD4FF26)
          ? const Color(0xFFD4FF26)
          : const Color(0xFF16A34A);
  }
}

/// Kolor tekstu na tle [eventTypeColor].
Color onEventTypeColor(String type, Color bg) =>
    bg == const Color(0xFFD4FF26) ? Colors.black : Colors.white;

/// Kolejność typów aktywności (kropki, legenda).
const List<String> kEventTypes = <String>[
  'training',
  'club_training',
  'match',
  'note',
];

String eventTypeLabel(String type) {
  switch (type) {
    case 'club_training':
      return 'Trening klubowy';
    case 'match':
      return 'Mecz';
    case 'note':
      return 'Notatka';
    default:
      return 'Trening';
  }
}
