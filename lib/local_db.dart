import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Lokalna "baza danych" na telefonie (zastępuje MongoDB z backendu).
/// Kolekcje i dokumenty zapisywane są jako JSON w `shared_preferences`.
class LocalDb {
  LocalDb._();

  static const String _prefix = 'mp.db.';
  // Osobna przestrzeń: wewnętrzne kopie nie trafiają do eksportu użytkownika.
  static const String _recoveryPrefix = 'mp.recovery.';
  static const Set<String> _collections = <String>{
    'trainings',
    'matches',
    'events',
    'plans',
    'chat_messages',
  };

  static String _slot(String collection, int number) =>
      '$_recoveryPrefix$collection.$number';

  static Future<void> _write(
    SharedPreferences sp,
    String key,
    String value,
  ) async {
    if (!await sp.setString(key, value)) {
      throw StateError('Nie udało się bezpiecznie zapisać danych ($key).');
    }
  }

  /// Parsujemy również strukturę (lista map z kluczami tekstowymi),
  /// bo poprawny JSON nie musi być poprawną kolekcją.
  static List<Map<String, dynamic>> _decodeList(String raw, String collection) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Nieprawidłowa kolekcja $collection.');
    }
    return decoded.map<Map<String, dynamic>>((item) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw FormatException('Nieprawidłowy rekord w kolekcji $collection.');
      }
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  static String? _validSnapshot(String? raw, String collection) {
    if (raw == null || raw.isEmpty) return null;
    try {
      _decodeList(raw, collection);
      return raw;
    } catch (_) {
      return null;
    }
  }

  /// Nie interpretujemy błędnego JSON-a jako pustego dziennika.
  /// Wracamy do najnowszego poprawnego z dwóch niezależnych slotów;
  /// przy braku obu kopii jawnie zgłaszamy uszkodzenie.
  static Future<String?> _safeRaw(
    SharedPreferences sp,
    String collection,
  ) async {
    final key = '$_prefix$collection';
    final raw = sp.getString(key);
    if (raw == null &&
        !sp.containsKey(_slot(collection, 1)) &&
        !sp.containsKey(_slot(collection, 2))) {
      return null; // Pierwsze uruchomienie, brak danych i kopii.
    }
    final valid = _validSnapshot(raw, collection);
    if (valid != null) return valid;
    for (final number in <int>[1, 2]) {
      final backup = _validSnapshot(
        sp.getString(_slot(collection, number)),
        collection,
      );
      if (backup != null) {
        await _write(sp, key, backup);
        return backup;
      }
    }
    throw FormatException(
      'Nie można odczytać zapisanych danych ($collection). '
      'Brak prawidłowej kopii awaryjnej. Przywróć dane z eksportu; '
      'nie dodawaj nowych wpisów.',
    );
  }

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
    final raw = await _safeRaw(sp, collection);
    return raw == null
        ? <Map<String, dynamic>>[]
        : _decodeList(raw, collection);
  }

  /// Dwa poprawnie zakodowane snapshoty: najnowszy i poprzedni.
  /// Najpierw chronimy nową wartość w backupie, dopiero potem
  /// zmieniamy główny klucz. Uszkodzenie danych blokuje zapis
  /// zamiast bez ostrzeżenia kasować kolekcję.
  static Future<void> saveList(
    String collection,
    List<Map<String, dynamic>> items,
  ) async {
    final sp = await _prefs();
    await _safeRaw(
      sp,
      collection,
    ); // Wykrywanie/naprawa uszkodzenia przed zapisem.
    final encoded = jsonEncode(items);
    _decodeList(encoded, collection);

    final recent = _validSnapshot(
      sp.getString(_slot(collection, 1)),
      collection,
    );
    if (recent != null && recent != encoded) {
      await _write(sp, _slot(collection, 2), recent);
    }
    await _write(sp, _slot(collection, 1), encoded);
    await _write(sp, '$_prefix$collection', encoded);
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
      final name = key.substring(_prefix.length);
      if (_collections.contains(name)) {
        out[name] = await list(
          name,
        ); // Odzyskaj albo zgłoś błąd - bez cichego pomijania.
      } else {
        try {
          out[name] = jsonDecode(raw);
        } catch (_) {
          // Pozostałe dokumenty nie są listami kolekcji.
        }
      }
    }
    return out;
  }

  static String _checkDate(dynamic value, String label) {
    if (value is! String || value.length < 10) {
      throw FormatException('Brak poprawnej daty w $label.');
    }
    final day = value.substring(0, 10);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw FormatException('Nieprawidłowa data w $label.');
    }
    final date = DateTime.tryParse(day);
    // Zmiana strefy czasowej nie może unieważniać poprawnej daty z pliku.
    if (date == null ||
        dateIsoDate(date) != day ||
        (value.length > 10 && DateTime.tryParse(value) == null)) {
      throw FormatException('Nieprawidłowa data w $label.');
    }
    return day;
  }

  static String dateIsoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static void _checkNumber(
    Map<String, dynamic> record,
    String key,
    int min,
    int max,
    String label,
  ) {
    if (!record.containsKey(key)) return; // Starsze wersje mogły nie mieć pola.
    final value = record[key];
    if (value is! num ||
        !value.isFinite ||
        value % 1 != 0 ||
        value < min ||
        value > max) {
      throw FormatException(
        'Nieprawidłowe pole $key w $label (dozwolone $min–$max).',
      );
    }
  }

  /// Jedna walidacja dla podglądu kopii i właściwego importu.
  /// Nie przepuszcza błędnych dat, ujemnych minut ani nieprawidłowych ocen.
  static void validateImport(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      final name = entry.key;
      if (name.isEmpty ||
          name.contains('..') ||
          name.contains('/') ||
          name.contains('\\') ||
          name.startsWith('_')) {
        throw const FormatException('Nieprawidłowa nazwa kolekcji w kopii.');
      }
      if (_collections.contains(name) && entry.value is! List) {
        throw FormatException('Nieprawidłowy typ kolekcji: $name.');
      }
      if (entry.value is List) {
        final rows = entry.value as List;
        for (var index = 0; index < rows.length; index++) {
          final raw = rows[index];
          if (raw is! Map || raw.keys.any((key) => key is! String)) {
            throw FormatException(
              'Nieprawidłowy rekord w $name, pozycja ${index + 1}.',
            );
          }
          if (!_collections.contains(name)) continue;
          final record = Map<String, dynamic>.from(raw);
          final label = '$name, wpis ${index + 1}';
          if (name == 'plans' || name == 'chat_messages') {
            if (record.containsKey('date')) _checkDate(record['date'], label);
            continue;
          }
          _checkDate(record['date'], label);
          if (record['id'] is! String ||
              (record['id'] as String).trim().isEmpty) {
            throw FormatException('Brak identyfikatora w $label.');
          }
          if (name == 'trainings') {
            _checkNumber(record, 'duration_min', 0, 600, label);
            _checkNumber(record, 'rating', 0, 5, label);
          } else if (name == 'matches') {
            _checkNumber(record, 'minutes_played', 0, 180, label);
            _checkNumber(record, 'goals', 0, 20, label);
            _checkNumber(record, 'assists', 0, 20, label);
            _checkNumber(record, 'rating', 0, 5, label);
          } else if (name == 'events') {
            _checkNumber(record, 'duration_min', 0, 600, label);
            _checkNumber(record, 'rating', 0, 5, label);
            _checkNumber(record, 'minutes_played', 0, 180, label);
            _checkNumber(record, 'goals', 0, 20, label);
            _checkNumber(record, 'assists', 0, 20, label);
          }
        }
      }
    }
  }

  /// Walidacja i odwracalny import: zapisujemy nowe wartości przed usunięciem starych.
  static Future<void> importAll(Map<String, dynamic> data) {
    return synchronized<void>(() async {
      validateImport(data);
      final prepared = <String, String>{};
      for (final entry in data.entries) {
        if (entry.key.isEmpty || entry.key.contains('..')) {
          throw const FormatException('Nieprawidłowa nazwa kolekcji');
        }
        if (_collections.contains(entry.key) && entry.value is! List) {
          throw FormatException('Nieprawidłowy typ: ${entry.key}');
        }
        if (entry.value is List &&
            !(entry.value as List).every((e) => e is Map)) {
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
      // Snapshoty techniczne trzymamy poza mp.db., by nie trafiały do eksportu.
      final oldRecovery = <String, String>{};
      for (final key in sp.getKeys()) {
        if (key.startsWith(_recoveryPrefix)) {
          final value = sp.getString(key);
          if (value != null) oldRecovery[key] = value;
        }
      }
      // Kopia bezpieczeństwa pozostaje dostępna także po imporcie.
      await _write(sp, 'mp.backup.before_import', jsonEncode(old));
      try {
        for (final entry in prepared.entries) {
          if (!await sp.setString(entry.key, entry.value)) {
            throw StateError('Nie udało się zapisać ${entry.key}');
          }
        }
        for (final key in old.keys) {
          if (!prepared.containsKey(key)) await sp.remove(key);
        }
        // Snapshoty muszą odpowiadać nowej bazie, a nie poprzedniemu importowi.
        for (final collection in _collections) {
          final value = prepared['$_prefix$collection'];
          if (value == null) {
            await sp.remove(_slot(collection, 1));
            await sp.remove(_slot(collection, 2));
          } else {
            await _write(sp, _slot(collection, 1), value);
            await _write(sp, _slot(collection, 2), value);
          }
        }
      } catch (_) {
        for (final entry in old.entries) {
          await sp.setString(entry.key, entry.value);
        }
        for (final key in prepared.keys) {
          if (!old.containsKey(key)) await sp.remove(key);
        }
        for (final key in sp.getKeys().where(
          (key) => key.startsWith(_recoveryPrefix),
        )) {
          if (!oldRecovery.containsKey(key)) await sp.remove(key);
        }
        for (final entry in oldRecovery.entries) {
          await sp.setString(entry.key, entry.value);
        }
        rethrow;
      }
    });
  }
}
