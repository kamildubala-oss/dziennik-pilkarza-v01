import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/screens/diary_screen.dart';
import 'package:dziennik_pilkarza/screens/calendar_screen.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';

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
    await LocalDb.setDoc('profile', {'name': 'Adam', 'club_days': []});
  });
  Widget app(Widget child) => MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
    home: Scaffold(body: child));

  testWidgets('all diary quick actions keep one shared font size and one line', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0]) {
      await tester.binding.setSurfaceSize(Size(width, 850));
      final selected = ValueNotifier(0);
      await tester.pumpWidget(app(DiaryScreen(selected: selected, index: 0, onOpenCoach: () {})));
      await tester.pumpAndSettle();
      final training = tester.widget<Text>(find.text('Zapisz trening'));
      final match = tester.widget<Text>(find.text('Zapisz mecz'));
      expect(training.maxLines, 1);
      expect(match.maxLines, 1);
      expect(tester.renderObject<RenderParagraph>(find.text('Zapisz trening')).didExceedMaxLines, false);
      expect(tester.renderObject<RenderParagraph>(find.text('Zapisz mecz')).didExceedMaxLines, false);
      expect(training.style!.fontSize, match.style!.fontSize);
      final now = DateTime.now();
      if (now.weekday != 7) {
        final future = dateIso(DateTime(now.year, now.month, now.day + 7 - now.weekday));
        await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == future));
        await tester.pumpAndSettle();
        final planTraining = tester.widget<Text>(find.text('Zaplanuj trening'));
        final planMatch = tester.widget<Text>(find.text('Zaplanuj mecz'));
        expect(planTraining.maxLines, 1);
        expect(planMatch.maxLines, 1);
        expect(tester.renderObject<RenderParagraph>(find.text('Zaplanuj trening')).didExceedMaxLines, false);
        expect(tester.renderObject<RenderParagraph>(find.text('Zaplanuj mecz')).didExceedMaxLines, false);
        expect(planTraining.style!.fontSize, training.style!.fontSize);
        expect(planMatch.style!.fontSize, training.style!.fontSize);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      selected.dispose();
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('club entry has calendar color and opens the shared editor with original data', (tester) async {
    await Api.createTraining(date: todayIso(), durationMin: 90, focuses: ['Gierka'],
      intensity: 'medium', rating: 4, wentWell: 'Podania', toImprove: '', notes: '', kind: 'club_training');
    final saved = (await Api.listTrainings()).single;
    final selected = ValueNotifier(0);
    await tester.pumpWidget(app(DiaryScreen(selected: selected, index: 0, onOpenCoach: () {})));
    await tester.pumpAndSettle();
    final entry = find.byKey(ValueKey('journal-entry-${saved.id}'));
    expect(find.descendant(of: entry, matching: find.byIcon(Icons.groups)), findsOneWidget);
    final iconBox = tester.widgetList<Container>(find.descendant(of: entry,
      matching: find.byType(Container))).where((w) => w.decoration is BoxDecoration)
      .firstWhere((w) => (w.decoration as BoxDecoration).color == eventTypeColor(AppColors.dark, 'club_training'));
    expect(iconBox.decoration, isNotNull);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final editor = tester.widget<LogSessionScreen>(find.byType(LogSessionScreen));
    expect(editor.editing!.id, saved.id);
    expect(editor.kind, 'club_training');
    expect(editor.mode, TrainingFormMode.editTraining);
    expect(find.text('Edytuj trening'), findsOneWidget);
    expect(await Api.listTrainings(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });

  testWidgets('coach secondary action has an opaque background over the image', (tester) async {
    final selected = ValueNotifier(0);
    await tester.pumpWidget(app(DiaryScreen(selected: selected, index: 0, onOpenCoach: () {})));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(find.ancestor(of: find.text('Zapytaj trenera'),
      matching: find.byType(TextButton)));
    expect(button.style!.backgroundColor!.resolve({}), isNot(Colors.transparent));
    expect(button.style!.side!.resolve({}), isNotNull);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });

  testWidgets('calendar retains today border when a different day is selected', (tester) async {
    final selected = ValueNotifier(1);
    await tester.pumpWidget(app(CalendarScreen(selected: selected, index: 1)));
    await tester.pumpAndSettle();
    final today = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Dzisiaj, ${todayIso()}');
    final other = find.byWidgetPredicate((w) => w is Semantics && w.properties.label != null &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(w.properties.label!)).first;
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(today).properties.selected, false);
    final box = tester.widget<Container>(find.descendant(of: today, matching: find.byType(Container)).first);
    expect((box.decoration as BoxDecoration).border, isNotNull);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });
}
