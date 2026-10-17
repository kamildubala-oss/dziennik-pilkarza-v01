import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/screens/log_match_screen.dart';
import 'package:dziennik_pilkarza/services/progress_calculator.dart';
import 'package:dziennik_pilkarza/services/skill_radar_service.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('trainings');
  });
  setUp(() async {
    for (final name in ['trainings', 'matches', 'events', 'plans']) {
      await LocalDb.saveList(name, []);
    }
  });

  Future<Training> training(int rating) => Api.createTraining(
    date: todayIso(), durationMin: 45, focuses: ['Strzał'],
    intensity: 'medium', rating: rating, wentWell: '', toImprove: '', notes: '',
  );

  test('unrated entries survive model decoding, backup and CSV export', () async {
    final saved = await training(0);
    expect(saved.rating, 0);
    expect(Training.fromJson({'id': 'legacy'}).rating, 0);
    expect(MatchEntry.fromJson({'id': 'legacy'}).rating, 0);
    final backup = await Api.exportBackup();
    await Api.importBackup(backup);
    expect((await Api.listTrainings()).single.rating, 0);
    final csv = await Api.exportTrainingsCsv();
    expect(csv, isNot(contains('0/5')));
    expect((await LocalDb.list('events')).single['description'], isNot(contains('ocena 0')));
  });

  test('average excludes missing ratings while activity totals retain them', () async {
    await training(0);
    await training(4);
    final stats = await ProgressCalculator.calculate();
    expect(stats.avgRating, 4);
    expect(stats.totalTrainings, 2);
    expect(stats.totalMinutes, 90);
    expect(stats.hasTopRating, false);
  });

  test('all unrated activities have no average and no top rating', () async {
    await training(0);
    final stats = await ProgressCalculator.calculate();
    expect(stats.avgRating, 0);
    expect(stats.hasTopRating, false);
    expect(SkillRadarService.ratingWeight(0), 1.0);
    expect(SkillRadarService.ratingWeight(null), 1.0);
  });

  testWidgets('untouched training form saves without assigning three stars', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(AppColors.dark, Brightness.dark),
      home: const LogSessionScreen(initialFocuses: ['Strzał']),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<RatingStars>(find.byType(RatingStars)).rating, 0);
    expect(find.text('Oceń trening (opcjonalnie)'), findsOneWidget);
    final save = find.byType(PrimaryButton);
    await tester.ensureVisible(save);
    await tester.runAsync(() async {
      await tester.tap(save);
      await LocalDb.synchronized<void>(() async {});
    });
    await tester.pumpAndSettle();
    expect((await Api.listTrainings()).single.rating, 0);
  });

  testWidgets('untouched match form saves without assigning three stars', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(AppColors.dark, Brightness.dark),
      home: const LogMatchScreen(),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<RatingStars>(find.byType(RatingStars)).rating, 0);
    expect(find.text('Oceń mecz (opcjonalnie)'), findsOneWidget);
    final save = find.byType(PrimaryButton);
    await tester.ensureVisible(save);
    await tester.runAsync(() async {
      await tester.tap(save);
      await LocalDb.synchronized<void>(() async {});
    });
    await tester.pumpAndSettle();
    expect((await Api.listMatches()).single.rating, 0);
  });

  testWidgets('rating can be consciously selected and cleared', (tester) async {
    var rating = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) => RatingStars(rating: rating,
        onChanged: (value) => setState(() => rating = value)),
    ))));
    expect(find.byIcon(Icons.star), findsNothing);
    await tester.tap(find.byIcon(Icons.star_outline).at(3));
    await tester.pump();
    expect(rating, 4);
    await tester.tap(find.text('Usuń ocenę'));
    await tester.pump();
    expect(rating, 0);
    expect(find.byIcon(Icons.star), findsNothing);
  });
}
