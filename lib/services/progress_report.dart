import 'dart:convert';
import '../local_db.dart';
import '../models.dart';
import '../utils.dart';
import 'progress_calculator.dart';
import 'skill_radar_service.dart';

/// Widok danych, bez migracji ani dodatkowych zapisów w bazie.
class ProgressReport {
  ProgressReport(this.stats, this.previous, this.entries, this.areas,
      this.strengths, this.planDays, this.fulfilledDays, this.rangeLabel);
  final Progress stats;
  final Progress? previous;
  final List<Map<String, dynamic>> entries;
  final Map<String, int> areas;
  final List<Map<String, dynamic>> strengths;
  final int planDays, fulfilledDays;
  final String rangeLabel;

  static DateTime startOfSeason(DateTime now) => DateTime(now.month >= 7 ? now.year : now.year - 1, 7);
  static Future<ProgressReport> load(int period, {DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = period == 0 ? null : period == -1 ? startOfSeason(today)
      : DateTime(today.year, today.month, today.day - period + 1);
    final since = start == null ? null : dateIso(start);
    final stats = await ProgressCalculator.calculate(asOf: now, since: since);
    final length = start == null ? 0 : DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays + 1;
    final previous = start == null ? null : await ProgressCalculator.calculate(asOf: now,
      since: dateIso(DateTime(start.year, start.month, start.day - length)),
      until: dateIso(DateTime(start.year, start.month, start.day - 1)));
    final entries = <Map<String, dynamic>>[
      for (final t in await LocalDb.list('trainings')) {...t, '_source': 'trainings'},
      for (final m in await LocalDb.list('matches')) {...m, '_source': 'matches'},
    ].where((e) {
      final day = first10((e['date'] ?? '').toString());
      final parsed = DateTime.tryParse(day);
      return parsed != null && dateIso(parsed) == day && day.compareTo(dateIso(today)) <= 0 &&
        (since == null || day.compareTo(since) >= 0);
    }).toList()..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    final history = await LocalDb.exportAll();
    final planned = <String, bool>{};
    for (final item in history.entries) {
      if (!item.key.startsWith('weekly_plan_') || item.value is! Map) continue;
      final days = (item.value as Map)['days'];
      if (days is! List) continue;
      for (final d in days.whereType<Map>()) {
        final day = first10((d['date'] ?? '').toString());
        if (DateTime.tryParse(day) == null || day.compareTo(dateIso(today)) >= 0 ||
            (since != null && day.compareTo(since) < 0)) continue;
        final focus = (d['focus'] ?? '').toString().toLowerCase();
        planned[day] = focus.contains('odpoczynek') || focus.contains('regeneracj') || focus == 'rest';
      }
    }
    final activeDays = entries.where((e) => e['kind'] != 'recovery').map((e) => first10((e['date'] ?? '').toString())).toSet();
    final fulfilled = planned.entries.where((d) => d.value ? !activeDays.contains(d.key) : activeDays.contains(d.key)).length;
    return ProgressReport(stats, previous, entries,
      SkillRadarService.areas(entries.where((e) => e['_source'] == 'trainings').toList()),
      entries.where((e) => (e['went_well'] ?? '').toString().trim().isNotEmpty).toList(),
      planned.length, fulfilled, '${since ?? 'Początek historii'} – ${dateIso(today)}');
  }
}

/// Ta sama uporządkowana próbka dla AI, offline i wykrywania zmian danych.
class ObservationSample {
  static List<Map<String, dynamic>> latest(List<Map<String, dynamic>> trainings,
      List<Map<String, dynamic>> matches) {
    final today = todayIso();
    final items = <Map<String, dynamic>>[
      for (final e in trainings) {...e, '_type': e['kind'] == 'club_training' ? 'Trening klubowy' : 'Trening'},
      for (final e in matches) {...e, '_type': 'Mecz'},
    ].where((e) => (e['to_improve'] ?? '').toString().trim().isNotEmpty &&
      DateTime.tryParse(first10((e['date'] ?? '').toString())) != null &&
      first10((e['date'] ?? '').toString()).compareTo(today) <= 0).toList()
      ..sort((a, b) {
        final date = (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString());
        return date != 0 ? date : '${a['_type']}:${a['id']}'.compareTo('${b['_type']}:${b['id']}');
      });
    return items.length > 50 ? items.sublist(items.length - 50) : items;
  }
  static String fingerprint(List<Map<String, dynamic>> items) => jsonEncode([
    for (final e in items) [e['_type'], e['id'], e['date'], e['focus'], e['opponent'], e['to_improve']]
  ]);
}
