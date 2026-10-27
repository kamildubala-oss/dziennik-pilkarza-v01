import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/screens/add_event_screen.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/screens/calendar_screen.dart';
import 'package:dziennik_pilkarza/screens/diary_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:dziennik_pilkarza/widgets/card_snap_physics.dart';

Widget app(Widget child) => MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
  home: Scaffold(body: child));

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
    await LocalDb.setDoc('profile', {'club_days': []});
  });

  testWidgets('individual and club plans contain only planning inputs', (tester) async {
    for (final kind in ['training', 'club_training']) {
      await tester.pumpWidget(app(AddEventScreen(key: ValueKey(kind),
        initialDate: '2026-12-15', initialType: kind)));
      expect(tester.widget<DateField>(find.byType(DateField)).controller.text, '2026-12-15');
      expect(find.text('Nad czym chcesz pracować?'), findsOneWidget);
      expect(find.text('Intensywność'), findsNothing);
      expect(find.byType(RatingStars), findsNothing);
      expect(find.text('Co było dobrze?'), findsNothing);
      expect(find.text('Co trzeba poprawić?'), findsNothing);
      expect(find.text('Notatki'), findsNothing);
    }
  });

  testWidgets('new plan saves no execution fields and does not create a journal entry', (tester) async {
    await tester.pumpWidget(app(const LogSessionScreen(isPlanned: true,
      initialDate: '2026-12-15', initialFocuses: ['Podania'], initialDuration: 30)));
    final save = find.byType(PrimaryButton);
    await tester.ensureVisible(save);
    await tester.runAsync(() async {
      await tester.tap(save);
      await LocalDb.synchronized<void>(() async {});
    });
    await tester.pumpAndSettle();
    expect(await Api.listTrainings(), isEmpty);
    final plan = (await LocalDb.list('events')).single;
    expect(plan['date'], '2026-12-15');
    expect(plan['duration_min'], 30);
    expect(plan['focuses'], ['Podania']);
    expect(plan['done'], false);
    for (final key in ['rating', 'intensity', 'went_well', 'to_improve', 'notes']) {
      expect(plan.containsKey(key), false, reason: key);
    }
  });

  testWidgets('execution forms keep evaluation and reflection without notes', (tester) async {
    for (final kind in ['training', 'club_training']) {
      await tester.pumpWidget(app(LogSessionScreen(key: ValueKey(kind), kind: kind)));
      expect(find.text('Nad czym pracowałeś'), findsOneWidget);
      expect(find.text('Intensywność'), findsOneWidget);
      expect(find.byType(RatingStars), findsOneWidget);
      expect(find.text('Co było dobrze?'), findsOneWidget);
      expect(find.text('Co trzeba poprawić?'), findsOneWidget);
      expect(find.text('Notatki'), findsNothing);
    }
  });

  testWidgets('calendar empty action uses selected date and Today resets date and month', (tester) async {
    final selected = ValueNotifier(1);
    await tester.pumpWidget(app(CalendarScreen(selected: selected, index: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final next = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    final add = find.text('Dodaj na ten dzień');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(tester.widget<DateField>(find.byType(DateField)).controller.text, dateIso(next));
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    final today = find.text('Dzisiaj');
    await tester.ensureVisible(today);
    await tester.tap(today);
    await tester.pumpAndSettle();
    expect(find.text(todayIso()), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });

  testWidgets('diary routes future days to planning and highlights today separately', (tester) async {
    final selected = ValueNotifier(0);
    await tester.pumpWidget(app(DiaryScreen(selected: selected, index: 0, onOpenCoach: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Zapisz trening'), findsOneWidget);
    expect(find.text('Zapisz mecz'), findsOneWidget);
    expect(find.text('OSTATNIE 5 WPISÓW'), findsOneWidget);
    final now = DateTime.now();
    final sunday = dateIso(DateTime(now.year, now.month, now.day + 7 - now.weekday));
    if (sunday.compareTo(todayIso()) > 0) {
      final future = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == sunday);
      await tester.tap(future);
      await tester.pumpAndSettle();
      expect(find.text('Zaplanuj trening'), findsOneWidget);
      expect(find.text('Zaplanuj mecz'), findsOneWidget);
      final current = tester.widget<Semantics>(find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.label == 'Dzisiaj, ${todayIso()}'));
      expect(current.properties.selected, false);
      await tester.ensureVisible(find.text('Zaplanuj trening'));
      await tester.tap(find.text('Zaplanuj trening'));
      await tester.pumpAndSettle();
      expect(tester.widget<AddEventScreen>(find.byType(AddEventScreen)).isPlanned, true);
      expect(tester.widget<DateField>(find.byType(DateField)).controller.text, sunday);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      final primary = find.text('Zaplanuj aktywność');
      await tester.ensureVisible(primary);
      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(tester.widget<DateField>(find.byType(DateField)).controller.text, sunday);
    }
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });

  test('streak label has correct Polish singular and plural', () {
    expect(streakDayLabel(0), '0 dni');
    expect(streakDayLabel(1), '1 dzień');
    expect(streakDayLabel(2), '2 dni');
    expect(streakDayLabel(21), '21 dni');
  });

  testWidgets('workout rail settles on complete cards after dragging', (tester) async {
    await tester.pumpWidget(app(Center(child: SizedBox(width: 300, height: 160,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        physics: const CardSnapPhysics(itemExtent: 188),
        padding: const EdgeInsets.only(right: 120),
        child: Row(children: [
          for (var i = 0; i < 7; i++) ...[
            SizedBox(width: 180, child: Text('Karta $i')),
            if (i < 6) const SizedBox(width: 8),
          ],
        ]))))));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(-245, 0));
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(find.byType(Scrollable));
    expect((state.position.pixels / 188) - (state.position.pixels / 188).round(), closeTo(0, .01));
  });
}
