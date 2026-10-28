import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/services/progress_calculator.dart';
import 'package:dziennik_pilkarza/screens/progress_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('trainings');
  });
  setUp(() async {
    for (final collection in ['trainings', 'matches', 'events', 'plans']) {
      await LocalDb.saveList(collection, []);
    }
  });

  Future<void> seed() async {
    await LocalDb.saveList('trainings', [
      {'id': 'individual', 'date': todayIso(), 'rating': 5},
      {'id': 'club', 'date': todayIso(), 'kind': 'club_training', 'rating': 0},
    ]);
    await LocalDb.saveList('matches', [
      {'id': 'match', 'date': todayIso(), 'rating': 3},
    ]);
    await LocalDb.saveList('events', [
      {'id': 'plan', 'date': todayIso(), 'type': 'club_training', 'rating': 5, 'done': false},
    ]);
  }

  test('counts separate training types and only valid submitted ratings', () async {
    await seed();
    final stats = await ProgressCalculator.calculate();
    expect(stats.totalTrainings, 2);
    expect(stats.totalIndividualTrainings, 1);
    expect(stats.totalClubTrainings, 1);
    expect(stats.ratedEntriesCount, 2);
    expect(stats.avgRating, 4);
    expect(stats.weekSessions.last, 3);
    await LocalDb.saveList('trainings', [
      {'id': 'unrated', 'date': todayIso()},
      {'id': 'invalid', 'date': todayIso(), 'rating': 7},
    ]);
    await LocalDb.saveList('matches', []);
    final unrated = await ProgressCalculator.calculate();
    expect(unrated.ratedEntriesCount, 0);
    expect(unrated.avgRating, 0);
  });

  testWidgets('screen shows one average, rated count and zero-height empty days', (tester) async {
    await seed();
    final selected = ValueNotifier(3);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
      home: Scaffold(body: ProgressScreen(selected: selected, index: 3))));
    await tester.pumpAndSettle();
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('Na podstawie 2 ocen'), findsOneWidget);
    expect(find.text('Śr. ocena T+M'), findsNothing);
    expect(find.text('Treningi indywidualne'), findsOneWidget);
    expect(find.text('Treningi klubowe'), findsOneWidget);
    expect(find.text('Liczba aktywności'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      expect(tester.getSize(find.byKey(ValueKey('week-bar-$i'))).height, 0);
    }
    expect(tester.getSize(find.byKey(const ValueKey('week-bar-6'))).height, greaterThan(0));
    expect(find.text('NAD CZYM WARTO POPRACOWAĆ'), findsOneWidget);
    expect(find.text('Dodaj obserwacje po treningach, aby otrzymać wskazówki'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });

  testWidgets('no ratings is explained as optional rather than a missing score', (tester) async {
    final selected = ValueNotifier(3);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.light, Brightness.light),
      home: Scaffold(body: ProgressScreen(selected: selected, index: 3))));
    await tester.pumpAndSettle();
    expect(find.text('Ocena jest opcjonalna'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });
  testWidgets('summary and all six metrics have equal sizes at narrow widths and larger text', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 1.4]) {
        await tester.binding.setSurfaceSize(Size(width, 850));
        final selected = ValueNotifier(3);
        await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale)), child: child!),
          home: Scaffold(body: ProgressScreen(selected: selected, index: 3))));
        await tester.pumpAndSettle();
        final streak = tester.getSize(find.byKey(const ValueKey('hero-DNI Z RZĘDU')));
        final rating = tester.getSize(find.byKey(const ValueKey('hero-ŚR. OCENA TRENINGÓW I MECZÓW')));
        expect(streak, rating);
        final sizes = [for (final label in ['Treningi indywidualne', 'Treningi klubowe', 'Mecze', 'Minuty', 'Gole', 'Asysty'])
          tester.getSize(find.byKey(ValueKey('metric-$label')))];
        for (final size in sizes) { expect(size, sizes.first); }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        selected.dispose();
      }
    }
  });

}
