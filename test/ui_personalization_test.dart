import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/services/achievement_service.dart';
import 'package:dziennik_pilkarza/services/drill_batch.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/widgets/player_jersey.dart';

void main() {
  test('seven unique suggestions and no overlap between consecutive batches', () {
    final library = List.generate(30, (i) => Drill.fromJson({'id': '$i', 'title': 'Trening $i'}));
    final batch = DrillBatch(random: Random(42));
    var previous = batch.current(library).map((d) => d.id).toSet();
    expect(previous, hasLength(7));
    for (var i = 0; i < 20; i++) {
      batch.next(library);
      final next = batch.current(library).map((d) => d.id).toSet();
      expect(next, hasLength(7));
      expect(previous.intersection(next), isEmpty);
      previous = next;
    }
    expect(DrillBatch().current([]), isEmpty);
    expect(DrillBatch().current(library.take(3).toList()), hasLength(3));
  });

  test('jersey colors persist and old profiles receive safe defaults', () {
    final old = Profile.fromJson({'name': 'Jan', 'jersey_number': 10});
    expect(old.jerseyColor, 0xFF2563EB);
    expect(old.jerseyNumberColor, 0xFFFFFFFF);
    final custom = Profile.fromJson({...old.toJson(), 'jersey_color': 0xFFDC2626,
      'jersey_number_color': 0xFFFACC15});
    final restored = Profile.fromJson(custom.toJson());
    expect(restored.jerseyColor, 0xFFDC2626);
    expect(restored.jerseyNumberColor, 0xFFFACC15);
    expect(restored.jerseyNumber, 10);
  });

  test('latest badge follows history dates rather than badge list priority', () {
    final matches = <Map<String, dynamic>>[
      {'date': '2026-10-01', 'goals': 3, 'rating': 5},
    ];
    final trainings = <Map<String, dynamic>>[
      {'date': '2026-10-10', 'duration_min': 45},
    ];
    expect(AchievementService.latestBadgeTitle({}, trainings, matches,
      asOf: DateTime(2026, 10, 11)), 'Pierwszy trening');
    expect(AchievementService.latestBadgeTitle({}, [], [],
      asOf: DateTime(2026, 10, 11)), isEmpty);
    expect(AchievementService.latestBadgeTitle({}, trainings, matches,
      asOf: DateTime(2026, 9, 30)), isEmpty);
  });

  test('light primary action has readable white text and a green accent', () {
    final colors = AppColors.light;
    final ratio = (colors.onBrandPrimary.computeLuminance() + .05) /
        (colors.brandPrimary.computeLuminance() + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
    expect(colors.brandPrimary, isNot(const Color(0xFF0F1115)));
  });

  testWidgets('jersey displays the player number in either theme', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(
        brightness == Brightness.light ? AppColors.light : AppColors.dark, brightness),
        home: const Scaffold(body: PlayerJersey(number: 45,
          color: Color(0xFFDC2626), numberColor: Color(0xFFFACC15)))));
      expect(find.text('45'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
