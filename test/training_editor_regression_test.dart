import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/screens/activity_editor.dart';
import 'package:dziennik_pilkarza/screens/calendar_screen.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/services/progress_calculator.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalDb.list('trainings');
  });
  setUp(() async {
    for (final collection in ['events', 'trainings', 'matches', 'plans']) {
      await LocalDb.saveList(collection, <Map<String, dynamic>>[]);
    }
  });

  Future<void> seed({bool planned = false, String kind = 'training'}) async {
    await Api.createTraining(
      date: todayIso(),
      durationMin: 45,
      focuses: ['Prowadzenie', 'Strzał'],
      intensity: 'high',
      rating: 4,
      wentWell: 'Podania',
      toImprove: 'Przyjęcie',
      notes: 'Notatka',
      isPlanned: planned,
      kind: kind,
    );
  }

  Future<void> openCalendar(WidgetTester tester, {bool planned = false}) async {
    final selected = ValueNotifier<int>(1);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppColors.dark, Brightness.dark),
        home: CalendarScreen(selected: selected, index: 1),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('Trening: Prowadzenie, Strzał');
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.byType(LogSessionScreen), findsOneWidget);
    final values = tester
        .widgetList<AppTextField>(find.byType(AppTextField))
        .map((field) => field.controller.text);
    expect(
      values,
      containsAll(
        planned ? ['45', 'Notatka'] : ['45', 'Podania', 'Przyjęcie', 'Notatka'],
      ),
    );
    if (planned) {
      expect(find.byType(RatingStars), findsNothing);
    } else {
      expect(tester.widget<RatingStars>(find.byType(RatingStars)).rating, 4);
    }
  }

  Future<void> saveChangedDuration(WidgetTester tester) async {
    final duration = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is AppTextField &&
            widget.keyboardType == TextInputType.number,
      ),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(duration);
    await tester.enterText(duration, '70');
    final save = find.byType(PrimaryButton);
    await tester.ensureVisible(save);
    // Mutacje bazy muszą zakończyć się w rzeczywistej strefie async:
    // jej statyczna kolejka jest współdzielona z następnymi testami.
    await tester.runAsync(() async {
      await tester.tap(save);
      await LocalDb.synchronized<void>(() async {});
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'calendar card edits completed training in place and synchronizes event',
    (tester) async {
      await tester.runAsync(() => seed());
      final original = (await LocalDb.list('trainings')).single;
      final event = (await LocalDb.list('events')).single;
      await openCalendar(tester);
      await saveChangedDuration(tester);
      final trainings = await LocalDb.list('trainings');
      final events = await LocalDb.list('events');
      expect(trainings, hasLength(1));
      expect(events, hasLength(1));
      expect(trainings.single['id'], original['id']);
      expect(trainings.single['duration_min'], 70);
      expect(events.single['id'], event['id']);
      expect(events.single['source_id'], original['id']);
      expect(events.single['duration_min'], 70);
      expect(events.single['done'], true);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('calendar plan uses same form and save does not complete it', (
    tester,
  ) async {
    await tester.runAsync(() => seed(planned: true));
    final event = (await LocalDb.list('events')).single;
    await openCalendar(tester, planned: true);
    await saveChangedDuration(tester);
    expect(await LocalDb.list('trainings'), isEmpty);
    final events = await LocalDb.list('events');
    expect(events, hasLength(1));
    expect(events.single['id'], event['id']);
    expect(events.single['duration_min'], 70);
    expect(events.single['done'], false);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('missing journal link blocks editor instead of editing plan', () async {
    final event = EventItem.fromJson({
      'id': 'broken',
      'date': todayIso(),
      'type': 'training',
      'source': 'trainings',
      'source_id': 'missing',
      'done': true,
    });
    await expectLater(activityEditor(event), throwsStateError);
    expect(await LocalDb.list('trainings'), isEmpty);
  });

  test(
    'profile club event uses shared form for editing and completion',
    () async {
      final event = EventItem.fromJson({
        'id': 'club',
        'date': todayIso(),
        'type': 'club_training',
        'source': 'club',
        'done': false,
        'duration_min': 90,
      });
      final completing = await activityEditor(event, complete: true);
      expect(completing, isA<LogSessionScreen>());
      expect((completing as LogSessionScreen).kind, 'club_training');
      expect(completing.mode, TrainingFormMode.complete);
    },
  );

  test('manual club plan changes survive profile synchronization', () async {
    final today = DateTime.now();
    await LocalDb.setDoc('profile', <String, dynamic>{
      'club_days': [today.weekday],
      'club_time': '17:30',
      'club_duration_min': 90,
    });
    await Api.synchronizeCalendar();
    final original = (await Api.listEvents()).firstWhere(
      (e) => e.date == todayIso(),
    );
    final moved = dateIso(DateTime(today.year, today.month, today.day + 1));
    await Api.updatePlannedActivity(
      original.id,
      date: moved,
      title: 'Trening klubowy: Strzał',
      description: 'Zmieniony termin',
      details: <String, dynamic>{
        'duration_min': 65,
        'focuses': ['Strzał'],
      },
    );
    await Api.synchronizeCalendar();
    final events = await Api.listEvents();
    final edited = events.singleWhere((e) => e.id == original.id);
    expect(edited.date, moved);
    expect(edited.durationMin, 65);
    expect(events.where((e) => e.date == todayIso()), isEmpty);
    expect(await LocalDb.list('trainings'), isEmpty);
  });

  test(
    'progress uses requested date for streak independently of display limit',
    () async {
      await LocalDb.saveList('trainings', [
        for (var day = 1; day <= 8; day++)
          <String, dynamic>{
            'id': 't$day',
            'date': '2026-10-${day.toString().padLeft(2, '0')}',
            'duration_min': 45,
            'rating': 3,
            'focuses': ['Strzał'],
          },
      ]);
      expect(
        (await ProgressCalculator.calculate(asOf: DateTime(2026, 10, 9)))
            .streakDays,
        8,
      );
      expect(
        (await ProgressCalculator.calculate(asOf: DateTime(2026, 10, 10)))
            .streakDays,
        0,
      );
    },
  );
}
