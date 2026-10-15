import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Lokalna "baza danych" na telefonie (zastępuje MongoDB z backendu).
/// Kolekcje i dokumenty zapisywane są jako JSON w `shared_preferences`.
class LocalDb {
  LocalDb._();

  static const String _prefix = 'mp.db.';
  static SharedPreferences? _sp;
  static Future<void> _lock = Future<void>.value();
  static final Random _rng = Random.secure();

  static Future<SharedPreferences> _prefs() async {
    return _sp ??= await SharedPreferences.getInstance();
  }

  /// Wykonuje operacje po kolei (bez wyścigów przy odczyt-zmiana-zapis).
  static Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _lock;
    _lock = completer.future.then((_) {}, onError: (Object _) {});
    previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static Future<List<Map<String, dynamic>>> list(String collection) async {
    final sp = await _prefs();
    final raw = sp.getString('$_prefix$collection');
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {
      // Uszkodzone dane - traktujemy jak pustą kolekcję.
    }
    return <Map<String, dynamic>>[];
  }

  static Future<void> saveList(
    String collection,
    List<Map<String, dynamic>> items,
  ) async {
    final sp = await _prefs();
    await sp.setString('$_prefix$collection', jsonEncode(items));
  }

  static Future<Map<String, dynamic>?> getDoc(String name) async {
    final sp = await _prefs();
    final raw = sp.getString('$_prefix$name');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Uszkodzony dokument.
    }
    return null;
  }

  static Future<void> setDoc(String name, Map<String, dynamic> doc) async {
    final sp = await _prefs();
    await sp.setString('$_prefix$name', jsonEncode(doc));
  }

  /// Losowy identyfikator w formacie UUID v4.
  static String newId() {
    String hex(int n) => List<String>.generate(
          n,
          (_) => _rng.nextInt(16).toRadixString(16),
        ).join();
    final variant = (8 + _rng.nextInt(4)).toRadixString(16);
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }

  /// Wszystkie dane aplikacji (kolekcje i dokumenty) - do kopii zapasowej.
  static Future<Map<String, dynamic>> exportAll() async {
    final sp = await _prefs();
    final out = <String, dynamic>{};
    for (final key in sp.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = sp.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        out[key.substring(_prefix.length)] = jsonDecode(raw);
      } catch (_) {
        // Pomijamy uszkodzone wpisy.
      }
    }
    return out;
  }

  /// Walidacja i odwracalny import: zapisujemy nowe wartości przed usunięciem starych.
  static Future<void> importAll(Map<String, dynamic> data) {
    return synchronized<void>(() async {
      final prepared = <String, String>{};
      const collections = <String>{'trainings', 'matches', 'events', 'plans'};
      for (final entry in data.entries) {
        if (entry.key.isEmpty || entry.key.contains('..')) {
          throw const FormatException('Nieprawidłowa nazwa kolekcji');
        }
        if (collections.contains(entry.key) && entry.value is! List) {
          throw FormatException('Nieprawidłowy typ: ${entry.key}');
        }
        if (entry.value is List && !(entry.value as List).every((e) => e is Map)) {
          throw FormatException('Nieprawidłowe rekordy: ${entry.key}');
        }
        prepared['$_prefix${entry.key}'] = jsonEncode(entry.value);
      }
      final sp = await _prefs();
      final old = <String, String>{};
      for (final key in sp.getKeys()) {
        if (key.startsWith(_prefix)) {
          final value = sp.getString(key);
          if (value != null) old[key] = value;
        }
      }
      // Kopia bezpieczeństwa pozostaje dostępna po nieudanym imporcie.
      await sp.setString('mp.backup.before_import', jsonEncode(old));
      try {
        for (final entry in prepared.entries) {
          if (!await sp.setString(entry.key, entry.value)) {
            throw StateError('Nie udało się zapisać ${entry.key}');
          }
        }
        for (final key in old.keys) {
          if (!prepared.containsKey(key)) await sp.remove(key);
        }
      } catch (_) {
        for (final entry in old.entries) {
          await sp.setString(entry.key, entry.value);
        }
        for (final key in prepared.keys) {
          if (!old.containsKey(key)) await sp.remove(key);
        }
        rethrow;
      }
    });
  }
}
