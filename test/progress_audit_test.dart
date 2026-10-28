import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/llm_settings.dart';
import 'package:dziennik_pilkarza/services/skill_radar_service.dart';
import 'package:dziennik_pilkarza/services/progress_report.dart';
import 'package:dziennik_pilkarza/services/achievement_service.dart';
import 'package:dziennik_pilkarza/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('trainings');
  });
  setUp(() async {
    for (final key in ['trainings', 'matches', 'events', 'plans']) {
      await LocalDb.saveList(key, []);
    }
    await LlmSettings.setMode('offline');
  });
  test('every selectable area counts once regardless of rating or other selections', () {
    for (final rating in [0, 1, 5]) {
      final entries = [{'date': todayIso(), 'rating': rating,
        'focuses': [...SkillRadarService.focusToAxis.keys, 'Podania']}];
      final counts = SkillRadarService.areas(entries);
      for (final key in SkillRadarService.focusToAxis.keys) { expect(counts[key], 1); }
      final axes = SkillRadarService.calculate(entries, []);
      for (final axis in SkillRadarService.axes) { expect(axes[axis], 1); }
    }
    expect(SkillRadarService.calculate([], [{'date': todayIso(), 'rating': 5}])['Mentalność'], 0);
  });
  test('seven-day window is inclusive, previous window disjoint, plans and future excluded', () async {
    await LocalDb.saveList('trainings', [
      {'id': 'boundary', 'date': '2026-10-22', 'duration_min': 40, 'focuses': ['Podania'], 'went_well': 'Przyjęcie'},
      {'id': 'today', 'date': '2026-10-28', 'duration_min': 20, 'kind': 'club_training', 'rating': 4},
      {'id': 'previous', 'date': '2026-10-21', 'duration_min': 30},
      {'id': 'future', 'date': '2026-10-29', 'duration_min': 90},
    ]);
    await LocalDb.saveList('events', [{'date': '2026-10-28', 'done': false, 'type': 'training'}]);
    final report = await ProgressReport.load(7, asOf: DateTime(2026, 10, 28));
    expect(report.stats.totalTrainings, 2);
    expect(report.stats.totalClubTrainings, 1);
    expect(report.stats.totalMinutes, 60);
    expect(report.stats.ratedEntriesCount, 1);
    expect(report.previous!.totalMinutes, 30);
    expect(report.areas['Podania'], 1);
    expect(report.strengths.single['id'], 'boundary');
    expect(report.entries.map((e) => e['id']), ['today', 'boundary']);
    expect(ProgressReport.startOfSeason(DateTime(2026, 1, 1)), DateTime(2025, 7, 1));
  });
  test('latest 50 observations are chronological across both collections and edits change signature', () {
    final trainings = List.generate(55, (i) => <String, dynamic>{'id': '$i',
      'date': dateIso(DateTime(2025, 1, i + 1)), 'to_improve': 'Podania'});
    final sample = ObservationSample.latest(trainings, [
      {'id': 'old', 'date': '2024-01-01', 'to_improve': 'Strzał'},
      {'id': 'new', 'date': todayIso(), 'to_improve': 'Koncentracja'}]);
    expect(sample.length, 50);
    expect(sample.last['id'], 'new');
    expect(sample.any((e) => e['id'] == 'old'), isFalse);
    final fingerprint = ObservationSample.fingerprint(sample);
    sample.last['to_improve'] = 'Nowa obserwacja';
    expect(ObservationSample.fingerprint(sample), isNot(fingerprint));
  });
  test('offline classification ignores area metadata and requires recurrence', () async {
    await LocalDb.saveList('trainings', [
      {'id': 'a', 'date': todayIso(), 'focus': 'Strzał', 'to_improve': 'koncentracja'},
      {'id': 'b', 'date': todayIso(), 'focus': 'Strzał', 'to_improve': 'koncentracja'},
      {'id': 'c', 'date': todayIso(), 'focus': 'Strzał', 'to_improve': 'podania'},
    ]);
    final result = await Api.analyzeWeakSpots();
    expect(result.weakSpots.map((e) => e.area), ['Mentalność']);
    expect(result.noteCount, 3);
    expect(result.rangeStart, todayIso());
    expect(result.sampleFingerprint, isNotEmpty);
    final restored = await Api.getWeakSpots();
    expect(restored!.sampleFingerprint, result.sampleFingerprint);
  });
  test('earned badge dates follow actual activity dates', () {
    final earned = AchievementService.earnedDates({}, [
      {'date': '2026-10-01', 'duration_min': 40},
    ], [
      {'date': '2026-10-02', 'goals': 1},
    ], asOf: DateTime(2026, 10, 28));
    expect(earned['Pierwszy trening'], '2026-10-01');
    expect(earned['Pierwszy gol'], '2026-10-02');
  });
}
