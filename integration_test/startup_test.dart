import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/main.dart' as app;
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/screens/home_shell.dart';
import 'package:dziennik_pilkarza/screens/calendar_screen.dart';
import 'package:dziennik_pilkarza/utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android release starts with existing data and legacy settings', (tester) async {
    // Test działa tylko w izolowanym emulatorze CI; nie dotyka danych użytkownika.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mp.settings.llm_api_key', 123);
    await prefs.setBool('mp.settings.coach_mode', true);
    await Api.createTraining(date: todayIso(), durationMin: 45,
      focuses: ['Strzał'], intensity: 'medium', rating: 0,
      wentWell: '', toImprove: '', notes: 'Zachowaj wpis po uruchomieniu');
    final before = (await Api.listTrainings()).map((t) => t.id).toSet();

    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 200),
      EnginePhase.sendSemanticsUpdate, const Duration(seconds: 30));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect((await Api.listTrainings()).map((t) => t.id).toSet(), before);
    expect(tester.takeException(), isNull);

    final calendar = find.descendant(of: find.byType(BottomNavigationBar),
      matching: find.text('Kalendarz'));
    await tester.tap(calendar);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.textContaining('Trening: Strzał'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
