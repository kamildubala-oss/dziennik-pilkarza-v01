import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:dziennik_pilkarza/main.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/llm_settings.dart';
import 'package:dziennik_pilkarza/widgets/startup_gate.dart';

void main() {
  testWidgets('first frame is visible before initialization completes', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: StartupGate(
      initialize: () => pending.future, child: const Text('Dziennik gotowy'))));
    expect(find.text('Przygotowuję Twój dziennik…'), findsOneWidget);
    expect(find.text('Dziennik gotowy'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Dziennik gotowy'), findsOneWidget);
  });
  testWidgets('initialization error shows retry instead of a blank screen', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: StartupGate(
      initialize: () async { if (++calls == 1) throw StateError('read failed'); },
      child: const Text('Dziennik gotowy'))));
    await tester.pumpAndSettle();
    expect(find.text('Nie udało się uruchomić aplikacji'), findsOneWidget);
    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pumpAndSettle();
    expect(find.text('Dziennik gotowy'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets('timeout stays visible and retry does not duplicate a pending storage operation', (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: StartupGate(
      timeout: const Duration(seconds: 1),
      initialize: () { calls++; return pending.future; },
      child: const Text('Dziennik gotowy'))));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Uruchamianie trwa zbyt długo'), findsOneWidget);
    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pump();
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Dziennik gotowy'), findsOneWidget);
  });
  testWidgets('app root renders startup without waiting for native preferences', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ChangeNotifierProvider(create: (_) => ThemeController(),
      child: const DziennikApp()));
    expect(find.byType(StartupGate), findsOneWidget);
    expect(find.text('Przygotowuję Twój dziennik…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('legacy settings types do not prevent launch or erase journal values', () async {
    SharedPreferences.setMockInitialValues({
      'mp.settings.llm_api_key': 123,
      'mp.settings.coach_mode': true,
      'mp.db.trainings': '[{"id":"preserve"}]',
    });
    await LlmSettings.load();
    expect(LlmSettings.hasKey, false);
    expect(LlmSettings.mode, 'auto');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mp.db.trainings'), '[{"id":"preserve"}]');
  });
}
