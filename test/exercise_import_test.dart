import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/offline_coach.dart';
import 'package:dziennik_pilkarza/screens/drill_screen.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> library;
  setUpAll(() async { library = await OfflineCoach.exercises(); });

  test('all 30 source exercises have one canonical entry with 12 new IDs', () async {
    final raw = jsonDecode(await rootBundle.loadString('assets/offline_coach/exercise_library_v2.json')) as Map;
    expect(raw['count'], library.length);
    expect(library.map((e) => e['id']).toSet().length, library.length);
    final imported = library.where((e) => e['import_package'] == 'baza_dziennika_pilkarza_v1').toList();
    expect(imported, hasLength(30));
    expect(imported.map((e) => e['source_exercise_id']).toSet(),
      {for (var i = 1; i <= 30; i++) 'EX${i.toString().padLeft(3, '0')}'});
    expect(imported.where((e) => (e['id'] as String).startsWith('v23_')), hasLength(12));
    expect(imported.singleWhere((e) => e['source_exercise_id'] == 'EX001')['id'], 'tech_first_touch');
    expect(imported.singleWhere((e) => e['source_exercise_id'] == 'EX026')['id'], 'men_reset_after_error');
    for (final e in imported) {
      expect(e['participants_max'], inInclusiveRange(1, 2));
      expect(e['requires_team'], false);
      expect(e['steps'], isNotEmpty);
      expect(e['source_refs'], isNotEmpty);
      expect(e['review_status'], 'do_weryfikacji_trenerskiej');
      expect(e['duration_min'], e['session_block_minutes']);
    }
  });

  test('imported exercises are exposed by the actual ready workouts API', () async {
    final cards = await Api.drills();
    expect(cards.map((d) => d.id).toSet().length, cards.length);
    for (final e in library.where((e) => e['import_package'] == 'baza_dziennika_pilkarza_v1')) {
      final card = cards.singleWhere((d) => d.id == e['id']);
      expect(card.title, e['title']);
      expect(card.steps.first, e['instructions']);
      expect(card.description, contains('Uczestnicy: ${e['participants_max']}'));
      expect(card.description, contains('Sprzęt:'));
      expect(card.description, contains('Wiek: od ${e['min_age']} lat.'));
      expect(card.durationMin, e['session_block_minutes']);
      expect(card.focus, isIn(['Prowadzenie', 'Strzał', 'Decyzyjność', 'Siła', 'Mentalność']));
      expect(card.source, isNot(contains('PZPN')));
    }
  });

  testWidgets('new task details open the journal form with the task duration and intensity', (tester) async {
    final task = (await Api.drills()).singleWhere((d) => d.id == 'v23_ex029');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
      home: DrillScreen(drill: task)));
    await tester.pumpAndSettle();
    expect(find.text('Zrozumieć rolę wahadłowego'), findsOneWidget);
    final save = find.byType(PrimaryButton);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final form = tester.widget<LogSessionScreen>(find.byType(LogSessionScreen));
    expect(form.initialDuration, 5);
    expect(form.initialIntensity, 'low');
    expect(tester.widgetList<AppTextField>(find.byType(AppTextField)).map((w) => w.controller.text), contains('5'));
  });
}
