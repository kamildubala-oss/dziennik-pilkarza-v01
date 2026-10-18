import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dziennik_pilkarza/config.dart';
import 'package:dziennik_pilkarza/llm.dart';

http.Response answer(String value) => http.Response(jsonEncode({
  'candidates': [{'content': {'parts': [{'text': value}]}}],
}), 200);

class TrackingClient extends MockClient {
  TrackingClient(Future<http.Response> Function(http.Request) handler) : super(handler);
  bool closed = false;
  @override
  void close() { closed = true; super.close(); }
}

void main() {
  testWidgets('key verification accepts an answer after the old 25 second cutoff', (tester) async {
    var requests = 0;
    ({String? error, bool networkError})? result;
    final work = http.runWithClient(() => Llm.testKey('slow-valid-key'), () => MockClient((request) async {
      requests++;
      expect(request.url.path, contains(AppConfig.llmFastModel));
      await Future<void>.delayed(const Duration(seconds: 30));
      return answer('OK');
    })).then((value) { result = value; });
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(result, isNotNull);
    expect(result!.error, isNull);
    expect(requests, 1);
    await work;
  });

  testWidgets('timeout closes the first client and tries the alternate model', (tester) async {
    final late = Completer<http.Response>();
    final clients = <TrackingClient>[];
    final models = <String>[];
    ({String? error, bool networkError})? result;
    final work = http.runWithClient(() => Llm.testKey('alternate-after-timeout'), () {
      final client = TrackingClient((request) async {
        models.add(request.url.path);
        if (models.length == 1) return await late.future;
        return answer('OK');
      });
      clients.add(client);
      return client;
    }).then((value) { result = value; });
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    expect(result, isNotNull);
    expect(result!.error, isNull);
    expect(models, hasLength(2));
    expect(models[0], isNot(models[1]));
    expect(clients.every((client) => client.closed), true);
    late.complete(answer('Spóźniona odpowiedź'));
    await tester.pump();
    await work;
  });

  testWidgets('both model timeouts terminate with a distinct message', (tester) async {
    final pending = <Completer<http.Response>>[];
    ({String? error, bool networkError})? result;
    final work = http.runWithClient(() => Llm.testKey('all-models-time-out'), () => MockClient((_) {
      final response = Completer<http.Response>();
      pending.add(response);
      return response.future;
    })).then((value) { result = value; });
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
    expect(result, isNotNull);
    expect(result!.error, contains('czas oczekiwania'));
    expect(result!.error, isNot(contains('Sprawdź internet')));
    expect(pending, hasLength(2));
    for (final response in pending) { response.complete(answer('Late')); }
    await tester.pump();
    await work;
  });
}
