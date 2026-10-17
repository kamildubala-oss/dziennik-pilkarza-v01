import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/llm_settings.dart';
import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/screens/coach_screen.dart';
import 'package:dziennik_pilkarza/services/coach_runtime.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';

http.Response gemini(String text) => http.Response(jsonEncode({
  'candidates': [{'content': {'parts': [{'text': text}]}}],
}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('trainings');
  });
  setUp(() async {
    for (final collection in ['trainings', 'matches', 'events', 'plans', 'chat_messages']) {
      await LocalDb.saveList(collection, []);
    }
    await LlmSettings.setMode('auto');
    await LlmSettings.clearCustomKey();
    CoachRuntime.reset();
  });
  Future<void> note() => Api.createTraining(date: todayIso(), durationMin: 45,
    focuses: ['Strzał'], intensity: 'medium', rating: 0,
    wentWell: '', toImprove: 'Poprawić strzał', notes: '').then((_) {});

  test('key alone does not confirm online; success records actual source', () async {
    await LlmSettings.setCustomKey('test-key');
    expect(CoachRuntime.last.value, isNull);
    await http.runWithClient(() => Api.chat('test', 'Jak poprawić strzał?'),
      () => MockClient((_) async => gemini('Odpowiedź Gemini')));
    expect(CoachRuntime.last.value?.source, 'online');
    final messages = await LocalDb.list('chat_messages');
    expect(messages.last['source'], 'online');
  });

  test('failed network request replaces previous online status with offline', () async {
    await LlmSettings.setCustomKey('test-key');
    CoachRuntime.record('online', 'rozmowa', DateTime.now().toIso8601String());
    await http.runWithClient(() => Api.chat('test', 'Jak poprawić strzał?'),
      () => MockClient((_) async => http.Response('unavailable', 503)));
    expect(CoachRuntime.last.value?.source, 'offline');
    expect((await LocalDb.list('chat_messages')).last['source'], 'offline');
  });

  test('forced offline never contacts Gemini even with a key', () async {
    await LlmSettings.setCustomKey('test-key');
    await LlmSettings.setMode('offline');
    var requests = 0;
    await http.runWithClient(() => Api.chat('test', 'Jak poprawić strzał?'),
      () => MockClient((_) async { requests++; return gemini('unexpected'); }));
    expect(requests, 0);
    expect(CoachRuntime.last.value?.source, 'offline');
  });

  test('analysis persists its own source and generation time after restart', () async {
    await note();
    await LlmSettings.setCustomKey('test-key');
    final result = await http.runWithClient(() => Api.analyzeWeakSpots(),
      () => MockClient((_) async => gemini(jsonEncode({'weak_spots': [
        {'area': 'Strzał', 'insight': 'Popraw celność', 'priority': 'medium'}
      ]}))));
    expect(result.source, 'online');
    expect(DateTime.tryParse(result.generatedAt), isNotNull);
    CoachRuntime.reset();
    await LlmSettings.setMode('offline');
    final saved = await Api.getWeakSpots();
    expect(saved?.source, 'online');
    expect(saved?.generatedAt, result.generatedAt);
  });

  test('invalid AI analysis and plan are marked offline after fallback', () async {
    await note();
    await LlmSettings.setCustomKey('test-key');
    await http.runWithClient(() async {
      final analysis = await Api.analyzeWeakSpots();
      expect(analysis.source, 'offline');
      final plan = await Api.generateWeeklyPlan();
      expect(plan.source, 'offline');
      expect((await Api.getWeeklyPlan())?.source, 'offline');
    }, () => MockClient((_) async => gemini('{}')));
  });

  test('legacy online mode maps to automatic and changing settings resets status', () async {
    CoachRuntime.record('online', 'rozmowa', '2026-10-17T12:00:00Z');
    await LlmSettings.setMode('online');
    expect(LlmSettings.mode, 'auto');
    expect(CoachRuntime.last.value, isNull);
  });

  test('legacy analysis does not invent source or date', () {
    final old = WeakSpotsPayload.fromJson({});
    expect(old.source, '');
    expect(CoachRuntime.sourceLabel(old.source), 'Źródło nie zostało zapisane');
    expect(CoachRuntime.dateLabel(old.generatedAt), 'data nie została zapisana');
  });

  testWidgets('hero follows actual runtime outcomes with green and red status', (tester) async {
    await LlmSettings.setCustomKey('test-key');
    final selected = ValueNotifier<int>(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
      home: Scaffold(body: CoachScreen(selected: selected, index: 0))));
    await tester.pumpAndSettle();
    expect(find.text('Połączenie jeszcze niesprawdzone'), findsOneWidget);
    CoachRuntime.record('online', 'rozmowa', '2026-10-17T12:00:00Z');
    await tester.pump();
    expect(tester.widget<Text>(find.text('Online')).style?.color, Colors.greenAccent);
    CoachRuntime.record('offline', 'rozmowa', '2026-10-17T12:01:00Z');
    await tester.pump();
    expect(tester.widget<Text>(find.text('Offline')).style?.color, Colors.redAccent);
  });
}
