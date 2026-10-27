import 'dart:convert';
import 'package:flutter/services.dart';

/// Autorska baza ćwiczeń v2.4, w całości dostępna bez sieci.
class OfflineCoach {
  OfflineCoach._();
  static List<Map<String, dynamic>>? _exercises;
  static Future<List<Map<String, dynamic>>> exercises() async {
    if (_exercises != null) return _exercises!;
    final raw = await rootBundle.loadString('assets/offline_coach/exercise_library_v2.json');
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    _exercises = (parsed['exercises'] as List).whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['requires_team'] != true && (e['participants_max'] is! num || (e['participants_max'] as num) <= 2))
        .toList();
    return _exercises!;
  }

  static Future<String> reply(String question) async {
    final q = question.toLowerCase();
    if (['ból', 'boli', 'uraz', 'kontuz', 'skręc'].any(q.contains)) {
      return 'Tryb offline — zdrowie jest najważniejsze. Przerwij ćwiczenie powodujące ból, poinformuj rodzica lub trenera i skonsultuj objawy z lekarzem. Nie trenuj przez ból.';
    }
    final list = await exercises();
    if (list.isEmpty) return 'Tryb offline: biblioteka ćwiczeń jest niedostępna.';
    final keywords = <String, List<String>>{
      'strzał': ['strzał', 'strzel', 'wykończ'],
      'podania': ['poda', 'przyję', 'technika'],
      'prowadzenie': ['prowad', 'drybling', 'kiwan'],
      'motoryka': ['szybko', 'siła', 'wytrzym', 'kondyc'],
      'taktyka': ['takty', 'decyzj', 'ustaw', 'gra'],
      'regeneracja': ['odpocz', 'regener', 'zmęcz'],
    };
    String? target;
    for (final e in keywords.entries) {
      if (e.value.any(q.contains)) {target = e.key; break;}
    }
    final matches = list.where((e) {
      if (target == null) return true;
      final combined = '${e['title']} ${e['area']} ${e['subarea']} ${e['description']} ${e['goal']}'.toLowerCase();
      return combined.contains(target);
    }).toList();
    final choices = matches.isEmpty ? list : matches;
    final exercise = choices[DateTime.now().day % choices.length];
    final steps = (exercise['steps'] as List?)?.take(5).map((e) => '- $e').join('\n') ?? '';
    return 'Trener offline • ${exercise['title']} (${exercise['duration_min']} min)\n\n'
        '${exercise['description']}\n\n$steps\n\n'
        'Odpowiedź na podstawie lokalnej bazy ćwiczeń; bez wysyłania danych.';
  }
}
