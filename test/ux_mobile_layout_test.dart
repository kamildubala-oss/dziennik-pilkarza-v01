import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/screens/diary_screen.dart';
import 'package:dziennik_pilkarza/screens/calendar_screen.dart';
import 'package:dziennik_pilkarza/screens/coach_screen.dart';
import 'package:dziennik_pilkarza/screens/progress_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('events');
  });
  for (final light in [false, true]) {
    for (final screen in ['diary', 'calendar', 'plan', 'exercises', 'chat', 'progress']) {
      testWidgets('$screen fits 320px with enlarged text (${light ? 'light' : 'dark'})', (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await LocalDb.importAll({});
          await Api.createTraining(date: todayIso(), durationMin: 45,
            focuses: ['Strzał', 'Prowadzenie'], intensity: 'high', rating: 0,
            wentWell: 'Podania', toImprove: 'Strzał z dystansu', notes: '');
          await Api.generateWeeklyPlan();
        });
        final selected = ValueNotifier<int>(0);
        final Widget page = switch (screen) {
          'diary' => DiaryScreen(selected: selected, index: 0, onOpenCoach: () {}),
          'calendar' => CalendarScreen(selected: selected, index: 0),
          'progress' => ProgressScreen(selected: selected, index: 0),
          _ => CoachScreen(selected: selected, index: 0,
            initialSection: screen == 'plan' ? 0 : screen == 'exercises' ? 1 : 2),
        };
        await tester.pumpWidget(ChangeNotifierProvider(create: (_) => ThemeController(),
          child: MaterialApp(theme: buildTheme(light ? AppColors.light : AppColors.dark,
            light ? Brightness.light : Brightness.dark),
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5)), child: child!),
            home: Scaffold(body: page))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        selected.dispose();
        await tester.runAsync(() async { await LocalDb.synchronized<void>(() async {}); });
      });
    }
  }
}
