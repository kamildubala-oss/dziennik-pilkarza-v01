import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/screens/calendar_screen.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/screens/training_details_screen.dart';
import 'package:dziennik_pilkarza/services/planned_training_defaults.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

EventItem plannedTraining({String? date}) => EventItem.fromJson({
  'id': 'plan-101',
  'date': date ?? '2026-10-13',
  'time': '17:30',
  'type': 'training',
  'title': 'Trening: Prowadzenie, Strzał',
  'description': 'Czas: 60 min',
  'done': false,
  'planned': true,
  'created_at': '2026-10-10',
  'focuses': <String>['Prowadzenie', 'Strzał'],
  'focus': 'Prowadzenie, Strzał',
  'duration_min': 60,
  'intensity': 'high',
  'rating': 4,
  'went_well': 'Dokładne podania',
  'to_improve': 'Gra słabszą nogą',
  'notes': 'Ćwiczenie podań',
});

Widget inApp(Widget child) => MaterialApp(
  theme: buildTheme(AppColors.dark, Brightness.dark),
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    await LocalDb.saveList('events', <Map<String, dynamic>>[]);
    await LocalDb.saveList('trainings', <Map<String, dynamic>>[]);
    await LocalDb.saveList('matches', <Map<String, dynamic>>[]);
  });

  test('structured planned training restores all previously saved fields', () {
    final fields = PlannedTrainingDefaults.fromEvent(plannedTraining());
    expect(fields.date, '2026-10-13');
    expect(fields.durationMin, 60);
    expect(fields.focuses, <String>['Prowadzenie', 'Strzał']);
    expect(fields.intensity, 'high');
    expect(fields.rating, 4);
    expect(fields.wentWell, 'Dokładne podania');
    expect(fields.toImprove, 'Gra słabszą nogą');
    expect(fields.notes, 'Ćwiczenie podań');
  });

  test('legacy plans recover rating, intensity, notes and focuses from description', () {
    final event = EventItem.fromJson({
      'id': 'old-plan',
      'date': '2026-10-12',
      'type': 'training',
      'title': 'Planowany trening',
      'time': '',
      'done': false,
      'created_at': '2026-10-11',
      'description': 'Czas: 75 min\nObszary: Siła, Mentalność\n'
          'Intensywność: high\nPlanowana ocena: 5/5\n'
          'Co było dobrze: Sprinty\nDo poprawy: Oddech\n'
          'Notatka: Rozciąganie',
    });
    final fields = PlannedTrainingDefaults.fromEvent(event);
    expect(fields.durationMin, 75);
    expect(fields.focuses, <String>['Siła', 'Mentalność']);
    expect(fields.intensity, 'high');
    expect(fields.rating, 5);
    expect(fields.wentWell, 'Sprinty');
    expect(fields.toImprove, 'Oddech');
    expect(fields.notes, 'Rozciąganie');
  });

  testWidgets('completion form shows prefilled plan and Trening wykonany action', (tester) async {
    await tester.pumpWidget(inApp(LogSessionScreen(
      completingEvent: plannedTraining(),
    )));

    final dateField = tester.widget<DateField>(find.byType(DateField));
    expect(dateField.controller.text, '2026-10-13');

    final chips = tester.widgetList<ChipOption>(find.byType(ChipOption)).toList();
    expect(chips.firstWhere((c) => c.label == 'Prowadzenie').selected, isTrue);
    expect(chips.firstWhere((c) => c.label == 'Strzał').selected, isTrue);
    expect(chips.firstWhere((c) => c.label == 'Wysoka').selected, isTrue);
    expect(tester.widget<RatingStars>(find.byType(RatingStars)).rating, 4);

    final values = tester
        .widgetList<AppTextField>(find.byType(AppTextField))
        .map((w) => w.controller.text)
        .toList();
    expect(values, containsAll(<String>[
      '60', 'Dokładne podania', 'Gra słabszą nogą',
    ]));
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).label,
        'Trening wykonany');
    expect(find.byType(TrainingDetailsScreen), findsNothing);
  });

  testWidgets('calendar checkmark immediately opens one prefilled completion form and saves linked training',
      (tester) async {
    final today = todayIso();
    await Api.createTraining(
      date: today,
      durationMin: 60,
      focuses: <String>['Prowadzenie', 'Strzał'],
      intensity: 'high',
      rating: 4,
      wentWell: 'Dokładne podania',
      toImprove: 'Gra słabszą nogą',
      notes: 'Ćwiczenie podań',
      isPlanned: true,
    );
    final original = (await LocalDb.list('events')).single;
    expect(await LocalDb.list('trainings'), isEmpty);

    final selected = ValueNotifier<int>(1);
    addTearDown(selected.dispose);
    await tester.pumpWidget(inApp(CalendarScreen(selected: selected, index: 1)));
    await tester.pumpAndSettle();

    final checkmark = find.byIcon(Icons.radio_button_unchecked);
    await tester.ensureVisible(checkmark);
    await tester.tap(checkmark);
    await tester.pumpAndSettle();

    expect(find.byType(TrainingDetailsScreen), findsNothing);
    expect(find.byType(LogSessionScreen), findsOneWidget);
    expect(tester.widget<RatingStars>(find.byType(RatingStars)).rating, 4);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).label,
        'Trening wykonany');

    final button = find.byType(PrimaryButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    final trainings = await LocalDb.list('trainings');
    final events = await LocalDb.list('events');
    expect(trainings, hasLength(1));
    expect(events, hasLength(1));
    expect(events.single['id'], original['id']);
    expect(events.single['done'], true);
    expect(events.single['source_id'], trainings.single['id']);
    expect(trainings.single['date'], today);
    expect(trainings.single['focuses'], <String>['Prowadzenie', 'Strzał']);
    expect(trainings.single['intensity'], 'high');
    expect(trainings.single['rating'], 4);
    expect(trainings.single['went_well'], 'Dokładne podania');
    expect(trainings.single['to_improve'], 'Gra słabszą nogą');
    expect(trainings.single['notes'], 'Ćwiczenie podań');
  });
}
