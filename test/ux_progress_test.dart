import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/services/progress_calculator.dart';
import 'package:dziennik_pilkarza/services/skill_radar_service.dart';
import 'package:dziennik_pilkarza/services/week_plan_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() async {
    await LocalDb.importAll({});
  });

  test(
    'unrated session survives backup and is excluded from averages',
    () async {
      await Api.createTraining(
        date: '2026-10-01',
        durationMin: 45,
        focuses: ['Strzał'],
        intensity: 'medium',
        rating: 0,
        wentWell: '',
        toImprove: '',
        notes: '',
      );
      await Api.createMatch(
        date: '2026-10-01',
        opponent: 'Rywal',
        result: '1:0',
        minutesPlayed: 60,
        goals: 1,
        assists: 0,
        rating: 4,
        wentWell: '',
        toImprove: '',
        notes: '',
      );
      final backup = await LocalDb.exportAll();
      LocalDb.validateImport(backup);
      await LocalDb.importAll(backup);
      expect((await Api.listTrainings()).single.rating, 0);
      final progress = await ProgressCalculator.calculate(
        asOf: DateTime(2026, 10, 2),
      );
      expect(progress.avgRating, 4);
      expect(progress.ratedCount, 1);
    },
  );
  test(
    'plan stores intention without speculative rating or performance',
    () async {
      await Api.createTraining(
        date: '2026-10-01',
        durationMin: 45,
        focuses: ['Strzał'],
        intensity: 'medium',
        rating: 5,
        wentWell: 'Nie wykonano',
        toImprove: 'Nie wykonano',
        notes: 'Piłka',
        isPlanned: true,
      );
      final event = (await LocalDb.list('events')).single;
      expect(event.containsKey('rating'), false);
      expect(event.containsKey('went_well'), false);
      expect(event['description'], isNot(contains('ocena')));
      expect(await Api.listTrainings(), isEmpty);
    },
  );
  test(
    'area counts ignore self-rating and do not infer mentality from matches',
    () {
      final counts = SkillRadarService.calculate(
        [
          {
            'date': '2026-10-01',
            'focuses': ['Strzał', 'Strzał', 'Prowadzenie'],
            'rating': 0,
          },
          {
            'date': '2026-09-30',
            'focuses': ['Strzał'],
            'rating': 5,
          },
          {
            'date': '2026-10-18',
            'focuses': ['Strzał'],
          },
        ],
        [
          {'date': '2026-10-01', 'rating': 5},
        ],
        since: '2026-10-01',
        until: '2026-10-14',
      );
      expect(counts['Strzał'], 1);
      expect(counts['Technika'], 1);
      expect(counts['Mentalność'], 0);
    },
  );
  test('weekly realization deduplicates links and requires journal proof and recovery confirmation', () {
    final events = <Map<String, dynamic>>[
      {
        'id': 'a',
        'date': '2026-10-12',
        'type': 'training',
        'planned': true,
        'done': true,
        'source': 'trainings',
        'source_id': 't',
      },
      {
        'id': 'b',
        'date': '2026-10-12',
        'type': 'match',
        'planned': true,
        'done': true,
        'source': 'matches',
        'source_id': 'missing',
      },
    ];
    final days = <Map<String, dynamic>>[
      {
        'date': '2026-10-12',
        'focus': 'Strzał',
        'calendar_event_ids': ['a', 'b'],
      },
      {'date': '2026-10-13', 'focus': 'Odpoczynek'},
      {'date': '2026-10-18', 'focus': 'Odpoczynek'},
    ];
    final progress = WeekPlanProgress.calculate(
      events,
      days,
      {'2026-10-13', '2026-10-18'},
      [
        {'id': 't'},
      ],
      [],
      asOf: DateTime(2026, 10, 17),
    );
    expect(progress.total, 4);
    expect(
      progress.done,
      2,
    ); // linked training + explicitly confirmed past recovery
  });
  test(
    'equal 14-day periods have no overlap and chart separates activity types',
    () async {
      await LocalDb.saveList('trainings', [
        {
          'id': 'a',
          'date': '2026-10-04',
          'kind': 'club_training',
          'focuses': ['Strzał'],
        },
        {
          'id': 'b',
          'date': '2026-10-03',
          'kind': 'training',
          'focuses': ['Siła'],
        },
      ]);
      await LocalDb.saveList('matches', [
        {'id': 'm', 'date': '2026-10-17'},
      ]);
      final progress = await ProgressCalculator.calculate(
        asOf: DateTime(2026, 10, 17),
      );
      expect(progress.skillRadarRecent['Strzał'], 1);
      expect(progress.skillRadarRecent['Motoryka'], 0);
      expect(progress.skillRadarPrevious['Motoryka'], 1);
      expect(progress.weekByType['match']!.last, 1);
      expect(progress.weekByType['club_training']!.last, 0);
      expect(progress.ratedCount, 0);
    },
  );
}
