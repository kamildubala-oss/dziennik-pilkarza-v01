import '../utils.dart';

class WeekPlanProgress {
  const WeekPlanProgress(this.done, this.total);
  final int done;
  final int total;

  /// Każde planowane wydarzenie liczymy raz, po ID; regenerację wyłącznie
  /// po świadomym potwierdzeniu. Ręczne terminy kalendarza mają pierwszeństwo.
  static WeekPlanProgress calculate(
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> planDays,
    Set<String> recoveryDays,
    List<Map<String, dynamic>> trainings,
    List<Map<String, dynamic>> matches, {
    required DateTime asOf,
  }) {
    final monday = DateTime(asOf.year, asOf.month, asOf.day - asOf.weekday + 1);
    final start = dateIso(monday);
    final end = dateIso(DateTime(monday.year, monday.month, monday.day + 6));
    final today = dateIso(asOf);
    String text(dynamic v) => v?.toString() ?? '';
    bool inWeek(String d) => d.compareTo(start) >= 0 && d.compareTo(end) <= 0;
    final targets = <String, bool>{};
    final byDate = <String, List<Map<String, dynamic>>>{};
    final trainingIds = trainings.map((t) => text(t['id'])).toSet();
    final matchIds = matches.map((m) => text(m['id'])).toSet();
    for (final e in events) {
      final date = first10(text(e['date']));
      if (!inWeek(date) ||
          !['training', 'club_training', 'match'].contains(e['type'])) {
        continue;
      }
      if (e['planned'] != true &&
          e['source'] != 'club' &&
          e['source'] != 'plan' &&
          text(e['planned_source']).isEmpty &&
          e['plan_link'] != true) {
        continue;
      }
      byDate.putIfAbsent(date, () => []).add(e);
      final sourceId = text(e['source_id']);
      final linked = e['source'] == 'matches'
          ? matchIds.contains(sourceId)
          : e['source'] == 'trainings' && trainingIds.contains(sourceId);
      targets['event:${e['id']}'] =
          e['done'] == true && linked && date.compareTo(today) <= 0;
    }
    for (final day in planDays) {
      final date = first10(text(day['date']));
      if (!inWeek(date)) continue;
      final focus = text(day['focus']).toLowerCase();
      final rest =
          focus.contains('odpoczynek') ||
          focus.contains('regeneracj') ||
          focus == 'rest';
      final ids =
          (day['calendar_event_ids'] as List?)?.map(text).toList() ??
          <String>[];
      if (ids.isNotEmpty) {
        // Powiązanie jest po ID także po ręcznej zmianie terminu.
        // Brakującego planu nie zaliczamy automatycznie jako wykonanego.
        for (final id in ids) {
          if (!events.any((e) => text(e['id']) == id)) {
            targets['missing:$id'] = false;
          }
        }
        continue;
      }
      if ((byDate[date] ?? []).isNotEmpty) continue;
      if (rest) {
        targets['rest:$date'] =
            recoveryDays.contains(date) && date.compareTo(today) <= 0;
      } else {
        targets['plan:$date:${day['title']}'] = false;
      }
    }
    return WeekPlanProgress(
      targets.values.where((v) => v).length,
      targets.length,
    );
  }
}
