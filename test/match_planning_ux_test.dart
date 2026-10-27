import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/screens/add_event_screen.dart';
import 'package:dziennik_pilkarza/screens/log_match_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('matches');
  });
  setUp(() async {
    for (final collection in ['trainings', 'matches', 'events', 'plans']) {
      await LocalDb.saveList(collection, []);
    }
  });
  Widget app(Widget child) => MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark), home: child);

  testWidgets('future match plan has opponent and date without result fields', (tester) async {
    await tester.pumpWidget(app(const AddEventScreen(initialDate: '2026-12-20', initialType: 'match')));
    expect(find.text('Przeciwnik'), findsOneWidget);
    expect(tester.widget<DateField>(find.byType(DateField)).controller.text, '2026-12-20');
    for (final label in ['Wynik', 'Minuty', 'Gole', 'Asysty', 'Co było dobrze?', 'Co poprawić?', 'Notatki']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byType(RatingStars), findsNothing);
  });

  testWidgets('saving a match plan stores no outcome and creates no played match', (tester) async {
    await tester.pumpWidget(app(const LogMatchScreen(isPlanned: true, initialDate: '2026-12-20')));
    final opponent = find.descendant(of: find.byWidgetPredicate((w) =>
      w is AppTextField && w.hint == 'np. Legia U15'), matching: find.byType(TextField));
    await tester.enterText(opponent, 'Skra');
    await tester.runAsync(() async {
      await tester.tap(find.byType(PrimaryButton));
      await LocalDb.synchronized<void>(() async {});
    });
    await tester.pumpAndSettle();
    expect(await Api.listMatches(), isEmpty);
    final event = (await LocalDb.list('events')).single;
    expect(event['opponent'], 'Skra');
    expect(event['date'], '2026-12-20');
    expect(event['done'], false);
    for (final key in ['result', 'rating', 'minutes_played', 'duration_min', 'goals', 'assists', 'went_well', 'to_improve', 'notes']) {
      expect(event.containsKey(key), false, reason: key);
    }
  });

  testWidgets('completion shows outcome fields but no notes or type selector', (tester) async {
    await tester.pumpWidget(app(LogMatchScreen(completingEvent: EventItem.fromJson({
      'id': 'plan', 'date': todayIso(), 'type': 'match', 'opponent': 'Skra',
    }), header: const Text('Typ'))));
    expect(find.text('Wynik'), findsOneWidget);
    expect(find.text('Minuty'), findsOneWidget);
    expect(find.byType(RatingStars), findsOneWidget);
    expect(find.text('Co było dobrze?'), findsOneWidget);
    expect(find.text('Co poprawić?'), findsOneWidget);
    expect(find.text('Notatki'), findsNothing);
    expect(find.text('Typ'), findsNothing);
  });

  testWidgets('editing preserves legacy notes while hiding notes and type', (tester) async {
    await tester.runAsync(() => Api.createMatch(date: todayIso(), opponent: 'Skra', result: '1:0',
      minutesPlayed: 60, goals: 1, assists: 0, rating: 4,
      wentWell: 'Podania', toImprove: '', notes: 'Dawna notatka'));
    final match = (await Api.listMatches()).single;
    await tester.pumpWidget(app(LogMatchScreen(editing: match, header: const Text('Typ'))));
    expect(find.text('Typ'), findsNothing);
    expect(find.text('Notatki'), findsNothing);
    final save = find.byType(PrimaryButton);
    await tester.ensureVisible(save);
    await tester.runAsync(() async {
      await tester.tap(save);
      await LocalDb.synchronized<void>(() async {});
    });
    await tester.pumpAndSettle();
    final updated = (await Api.listMatches()).single;
    expect(updated.id, match.id);
    expect(updated.notes, 'Dawna notatka');
    expect(updated.opponent, 'Skra');
  });
}
