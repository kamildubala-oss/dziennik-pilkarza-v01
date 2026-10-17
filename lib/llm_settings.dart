import 'package:shared_preferences/shared_preferences.dart';
import 'services/coach_runtime.dart';


/// Klucz API trenera AI.
///
/// Zawodnik może wpisać własny klucz (Ustawienia w profilu).
/// Bez klucza trener działa wyłącznie offline.
/// Własny klucz jest zapisywany tylko na telefonie, poza bazą danych
/// aplikacji - nie trafia więc do eksportowanej kopii zapasowej.
class LlmSettings {
  LlmSettings._();

  static const String _key = 'mp.settings.llm_api_key';
  static String _custom = '';
  static const String _modeKey = 'mp.settings.coach_mode';
  static String _mode = 'auto'; // auto | offline | online
  static String get mode => _mode;
  static bool get forceOffline => _mode == 'offline';
  static bool get allowNetwork => !forceOffline && hasKey;

  static Future<void> setMode(String value) async {
    if (!<String>['auto', 'offline', 'online'].contains(value)) return;
    final sp = await SharedPreferences.getInstance();
    _mode = value == 'online' ? 'auto' : value;
    CoachRuntime.reset();
    await sp.setString(_modeKey, _mode);
  }

  /// Wczytuje zapisany klucz (wywoływane przy starcie aplikacji).
  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _custom = (sp.getString(_key) ?? '').trim();
    _mode = sp.getString(_modeKey) == 'offline' ? 'offline' : 'auto';
  }

  /// Klucz używany w zapytaniach do AI.
  static String get activeKey =>
      _custom;

  /// Czy używany jest własny klucz zawodnika.
  static bool get usingCustom => _custom.isNotEmpty;

  /// Czy w ogóle jest jakiś klucz (inaczej tryb offline).
  static bool get hasKey => activeKey.isNotEmpty;

  /// Zamaskowany klucz do wyświetlenia, np. "AQ.Ab8R••••L-g".
  static String mask(String key) {
    final k = key.trim();
    if (k.length <= 10) return '••••';
    return '${k.substring(0, 6)}••••${k.substring(k.length - 4)}';
  }

  static Future<void> setCustomKey(String key) async {
    final sp = await SharedPreferences.getInstance();
    _custom = key.trim();
    CoachRuntime.reset();
    await sp.setString(_key, _custom);
  }

  /// Usuwa własny klucz; trener wraca do trybu offline.
  static Future<void> clearCustomKey() async {
    final sp = await SharedPreferences.getInstance();
    _custom = '';
    CoachRuntime.reset();
    await sp.remove(_key);
  }
}
