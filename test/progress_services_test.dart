import 'package:flutter_test/flutter_test.dart';
import 'package:dziennik_pilkarza/services/streak_service.dart';
import 'package:dziennik_pilkarza/services/skill_radar_service.dart';

void main() {
  final today = DateTime(2026, 10, 15);

  group('StreakService', () {
    test('consecutive days ending yesterday remain active', () {
      expect(
        StreakService.calculate([
          '2026-10-10', '2026-10-11', '2026-10-12',
          '2026-10-13', '2026-10-14',
        ], asOf: today),
        5,
      );
    });

    test('the order of entries and duplicate sessions on the same date do not matter', () {
      expect(
        StreakService.calculate([
          '2026-10-14', '2026-10-12', '2026-10-14',
          '2026-10-10', '2026-10-13', '2026-10-11',
        ], asOf: today),
        5,
      );
    });

    test('a missing day ends the latest streak', () {
      expect(
        StreakService.calculate([
          '2026-10-09', '2026-10-10',
          '2026-10-12', '2026-10-13', '2026-10-14',
        ], asOf: today),
        3,
      );
    });

    test('date boundaries between months and years are handled', () {
      expect(
        StreakService.calculate([
          '2025-12-30', '2025-12-31', '2026-01-01', '2026-01-02',
        ], asOf: DateTime(2026, 1, 3)),
        4,
      );
    });

    test('future dates and invalid dates do not contribute to the streak', () {
      expect(
        StreakService.calculate([
          '2026-10-13', '2026-10-14', '2026-10-16',
          'not-a-date', '2026-02-30',
        ], asOf: today),
        2,
      );
    });

    test('empty journal gives zero, one completed day gives one', () {
      expect(StreakService.calculate([], asOf: today), 0);
      expect(StreakService.calculate(['2026-10-10'], asOf: today), 0);
      expect(StreakService.calculate(['2026-10-15'], asOf: today), 1);
    });

    test('historical streak expires after a gap before yesterday', () {
      expect(StreakService.calculate(['2026-10-10', '2026-10-11'], asOf: today), 0);
      expect(StreakService.calculate(['2026-10-13', '2026-10-14', '2026-10-15'], asOf: today), 3);
    });

    test('saved date strings including a time are normalized', () {
      expect(
        StreakService.calculate([
          '2026-10-13T12:00:00.000Z', '2026-10-14',
        ], asOf: today),
        2,
      );
    });
  });

  test('SkillRadarService returns expected skill axes', () {
    final radar = SkillRadarService.calculate([
      <String, dynamic>{
        'date': '2026-10-14',
        'focuses': <String>['Prowadzenie', 'Strzał'],
        'rating': 5,
      },
    ], <Map<String, dynamic>>[]);
    expect(radar['Technika'], 6);
    expect(radar['Strzał'], 6);
    expect(radar['Taktyka'], 0);
  });
}

