import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/llm.dart';
import 'package:dziennik_pilkarza/llm_settings.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/screens/ai_key_screen.dart';
import 'package:dziennik_pilkarza/services/coach_runtime.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';

http.Response answer(String text) => http.Response(jsonEncode({
  'candidates': [{'content': {'parts': [{'text': text}]}}],
}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var sequence = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('trainings');
  });
  setUp(() async {
    for (final name in ['trainings', 'matches', 'events', 'plans', 'chat_messages']) {
      await LocalDb.saveList(name, []);
    }
    await LlmSettings.setMode('auto');
    await LlmSettings.setCustomKey('unit-key-${++sequence}');
  });
  Future<void> note() => Api.createTraining(date: todayIso(), durationMin: 45,
    focuses: ['Strzał'], intensity: 'medium', rating: 0,
    wentWell: '', toImprove: 'Poprawić strzał', notes: '').then((_) {});

  test('catalog access alone cannot produce a successful key check', () async {
    var generated = 0;
    final result = await http.runWithClient(() => Llm.testKey('candidate-key'),
      () => MockClient((request) async {
        if (request.method == 'GET') return http.Response('{"models":[]}', 200);
        generated++;
        return http.Response('Forbidden: candidate-key secret response', 403);
      }));
    expect(generated, greaterThan(0));
    expect(result.error, contains('403'));
    expect(result.error, isNot(contains('candidate-key')));
    expect(result.error, isNot(contains('secret response')));
    expect(result.networkError, false);
  });

  test('key check generates with the submitted key and never saves it', () async {
    var requests = 0;
    final savedKey = LlmSettings.activeKey;
    final result = await http.runWithClient(() => Llm.testKey('new-key'),
      () => MockClient((request) async {
        requests++;
        expect(request.method, 'POST');
        expect(request.url.path, endsWith(':generateContent'));
        expect(request.headers['x-goog-api-key'], 'new-key');
        expect(request.url.query, isNot(contains('new-key')));
        final body = jsonDecode(request.body) as Map;
        expect(body['contents'][0]['parts'][0]['text'], 'Napisz tylko OK.');
        return answer('OK');
      }));
    expect(result.error, isNull);
    expect(requests, 1);
    expect(LlmSettings.activeKey, savedKey);
  });

  test('quota failure is not classified as a working key or network problem', () async {
    final result = await http.runWithClient(() => Llm.testKey(LlmSettings.activeKey),
      () => MockClient((_) async => http.Response('quota exhausted', 429)));
    expect(result.error, contains('429'));
    expect(result.networkError, false);
  });

  test('retired models trigger paginated discovery and reuse a verified text model', () async {
    var catalogs = 0;
    var generations = 0;
    const discovered = 'gemini-9.1-flash-lite';
    await http.runWithClient(() async {
      expect(await Llm.complete(system: 'Test', messages: [{'role': 'user', 'content': 'Hej'}]), 'Działa');
      final before = catalogs;
      expect(await Llm.complete(system: 'Test', messages: [{'role': 'user', 'content': 'Hej'}]), 'Działa');
      expect(catalogs, before);
    }, () => MockClient((request) async {
      if (request.method == 'GET') {
        catalogs++;
        if (request.url.queryParameters['pageToken'] == null) {
          return http.Response(jsonEncode({'models': [
            {'name': 'models/gemini-flash-image', 'supportedGenerationMethods': ['generateContent']},
            {'name': 'models/gemini-flash-embedding', 'supportedGenerationMethods': ['embedContent']},
          ], 'nextPageToken': 'second'}), 200);
        }
        expect(request.url.queryParameters['pageToken'], 'second');
        return http.Response(jsonEncode({'models': [
          {'name': 'models/$discovered', 'supportedGenerationMethods': ['generateContent']}
        ]}), 200);
      }
      generations++;
      return request.url.path.contains(discovered) ? answer('Działa') : http.Response('retired', 404);
    }));
    expect(catalogs, 2);
    expect(generations, greaterThanOrEqualTo(3));
  });

  test('chat, analysis and seven day plan all use real generation path', () async {
    await note();
    var calls = 0;
    await http.runWithClient(() async {
      expect(await Api.chat('online', 'Jak trenować?'), 'Odpowiedź online');
      final analysis = await Api.analyzeWeakSpots();
      expect(analysis.source, 'online');
      expect(analysis.notice, isEmpty);
      expect(analysis.weakSpots.single.area, 'Strzał');
      final plan = await Api.generateWeeklyPlan();
      expect(plan.source, 'online');
      expect(plan.notice, isEmpty);
      expect(plan.days, hasLength(7));
      expect(plan.days.any((day) => day.title == 'Plan Gemini'), true);
    }, () => MockClient((request) async {
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map;
      calls++;
      if (calls == 1) return answer('Odpowiedź online');
      expect(body['generationConfig']['responseMimeType'], 'application/json');
      if (calls == 2) return answer(jsonEncode({'weak_spots': [
        {'area': 'Strzał', 'insight': 'Popracuj nad celnością', 'priority': 'medium'}
      ]}));
      return answer(jsonEncode({'days': List.generate(7, (_) => {
        'title': 'Plan Gemini', 'focus': 'Strzał', 'duration_min': 30,
        'intensity': 'medium', 'description': 'Ćwicz celność', 'steps': ['Rozgrzewka', 'Strzały'],
      })}));
    }));
    expect(calls, 3);
  });

  test('valid AI analysis without weak spots stays online without invented findings', () async {
    await note();
    final result = await http.runWithClient(() => Api.analyzeWeakSpots(),
      () => MockClient((_) async => answer('{"weak_spots":[]}')));
    expect(result.source, 'online');
    expect(result.weakSpots, isEmpty);
    expect(result.notice, isEmpty);
  });

  test('fallback records the quota reason for every feature without leaking response data', () async {
    await note();
    await http.runWithClient(() async {
      await Api.chat('offline', 'Jak trenować?');
      expect(CoachRuntime.last.value?.source, 'offline');
      expect(CoachRuntime.last.value?.notice, contains('429'));
      final plan = await Api.generateWeeklyPlan();
      expect(plan.source, 'offline');
      expect(plan.notice, contains('429'));
      final analysis = await Api.analyzeWeakSpots();
      expect(analysis.source, 'offline');
      expect(analysis.notice, contains('429'));
      expect(analysis.notice, isNot(contains('private response')));
    }, () => MockClient((_) async => http.Response('private response', 429)));
  });

  test('network failure gives a safe message without probing further models', () async {
    var requests = 0;
    final result = await http.runWithClient(() => Llm.testKey('network-key'),
      () => MockClient((_) async {
        requests++;
        throw http.ClientException('https://example.invalid?key=network-key');
      }));
    expect(result.networkError, true);
    expect(result.error, isNot(contains('network-key')));
    expect(requests, 1);
  });

  testWidgets('successful key test explains forced offline and requires explicit mode change', (tester) async {
    await LlmSettings.setMode('offline');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
      home: const AiKeyScreen()));
    final check = find.text('Sprawdź generowanie Gemini');
    await tester.ensureVisible(check);
    await tester.runAsync(() => http.runWithClient(() async {
      await tester.tap(check);
    }, () => MockClient((_) async => answer('OK'))));
    await tester.pumpAndSettle();
    expect(find.text('Generowanie Gemini działa, ale wybrano Tylko offline.'), findsOneWidget);
    expect(LlmSettings.forceOffline, true);
    final enable = find.text('Włącz tryb automatyczny');
    await tester.ensureVisible(enable);
    await tester.runAsync(() async { await tester.tap(enable); });
    await tester.pumpAndSettle();
    expect(LlmSettings.mode, 'auto');
  });
}
