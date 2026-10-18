import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'llm_settings.dart';

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode, this.networkError = false, this.timedOut = false});
  final String message;
  final int? statusCode;
  final bool networkError;
  final bool timedOut;
  @override
  String toString() => message;
}

/// Ten sam klient generateContent służy do testu klucza i pracy trenera.
class Llm {
  Llm._();
  static int? _workingKeyFingerprint;
  static String? _workingModel;
  static bool get enabled => LlmSettings.allowNetwork;
  static String get offlineReason => LlmSettings.forceOffline
      ? 'Włączony tryb Tylko offline. Wybierz Automatyczny w profilu, aby używać Gemini.'
      : 'Brak zapisanego klucza API. Trener korzysta z pakietu offline.';

  static String explain(Object error) => error is LlmException
      ? error.message : 'Nie udało się odczytać odpowiedzi Gemini. Użyto trenera offline.';

  /// Krótkie, rzeczywiste generowanie; zużywa limit generowania API.
  /// Nie zapisuje klucza ani nie wysyła danych zawodnika.
  static Future<({String? error, bool networkError})> testKey(String key) async {
    try {
      await _complete(key.trim(), 'Odpowiedz krótko.', [
        {'role': 'user', 'content': 'Napisz tylko OK.'},
      ], true, false);
      return (error: null, networkError: false);
    } on LlmException catch (e) {
      return (error: e.message, networkError: e.networkError);
    }
  }

  static Future<String> complete({
    required String system,
    required List<Map<String, String>> messages,
    bool fast = true,
    bool json = false,
  }) => _complete(LlmSettings.activeKey, system, messages, fast, json);

  static Future<String> _complete(String key, String system,
      List<Map<String, String>> messages, bool fast, bool json) async {
    if (key.isEmpty) throw LlmException('Brak klucza API Gemini.');
    final watch = Stopwatch()..start();
    Duration remaining({bool catalog = false}) {
      final left = const Duration(minutes: 2) - watch.elapsed;
      if (left <= Duration.zero) throw _timeout();
      final limit = Duration(seconds: catalog ? 15 : 60);
      return left < limit ? left : limit;
    }
    final models = <String>{
      if (_workingKeyFingerprint == key.hashCode && _workingModel != null) _workingModel!,
      if (fast) AppConfig.llmFastModel,
      AppConfig.llmModel,
      if (!fast) AppConfig.llmFastModel,
    }.toList();
    LlmException? failure;
    var discovered = false;
    final tried = <String>{};
    while (models.isNotEmpty && tried.length < 4) {
      final model = models.removeAt(0);
      if (!tried.add(model)) continue;
      try {
        final result = await _completeWith(model, key, system, messages, json,
          timeout: remaining());
        _workingKeyFingerprint = key.hashCode;
        _workingModel = model;
        return result;
      } on LlmException catch (e) {
        // Brak sieci kończy próbę; opóźnienie modelu pozwala użyć zapasowego.
        if (e.networkError && !e.timedOut) rethrow;
        if (failure == null || e.statusCode != 404) failure = e;
        if (e.statusCode == 404 && !discovered) {
          discovered = true;
          try {
            final available = await _availableModels(key, () => remaining(catalog: true));
            final fresh = available.where((m) => !tried.contains(m) && !models.contains(m)).take(2);
            models.insertAll(0, fresh);
          } on LlmException catch (catalogError) {
            if (catalogError.networkError && !catalogError.timedOut) rethrow;
            if (failure.statusCode == 404) failure = catalogError;
          }
        }
      }
    }
    throw failure ?? LlmException('Brak dostępnego modelu tekstowego Gemini dla tego klucza.');
  }

  static LlmException _timeout() => LlmException(
    'Przekroczono czas oczekiwania na Gemini. Usługa lub połączenie mogą być opóźnione. Spróbuj ponownie później.',
    networkError: true, timedOut: true);

  static LlmException _httpFailure(int code) => LlmException(switch (code) {
    400 => 'Gemini odrzucił żądanie (400). Sprawdź klucz i konfigurację projektu Google AI Studio.',
    401 => 'Gemini nie uwierzytelnił klucza (401). Sprawdź klucz API.',
    403 => 'Brak uprawnień do generowania Gemini (403). Sprawdź ograniczenia klucza i dostęp projektu w Google AI Studio.',
    404 => 'Wybrany model Gemini nie jest dostępny dla tego klucza (404).',
    429 => 'Przekroczony lub niedostępny limit generowania Gemini (429). Sprawdź limity projektu w Google AI Studio lub spróbuj później.',
    500 || 502 || 503 || 504 => 'Gemini jest chwilowo niedostępne ($code). Spróbuj ponownie później.',
    _ => 'Gemini odrzucił żądanie ($code). Sprawdź ustawienia API w Google AI Studio.',
  }, statusCode: code);

  static Future<Map<String, dynamic>> _send(
      Future<http.Response> Function(http.Client) request, {required Duration timeout}) async {
    http.Response res;
    final client = http.Client();
    try {
      res = await request(client).timeout(timeout);
    } on TimeoutException {
      throw _timeout();
    } catch (_) {
      throw LlmException('Nie udało się połączyć z Gemini. Sprawdź internet i spróbuj ponownie.', networkError: true);
    } finally {
      client.close();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) throw _httpFailure(res.statusCode);
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) { /* Nie ujawniamy treści odpowiedzi ani klucza w błędzie. */ }
    throw LlmException('Gemini zwróciło nieprawidłową odpowiedź. Spróbuj ponownie.');
  }

  static Future<List<String>> _availableModels(String key, Duration Function() timeout) async {
    final names = <String>{};
    String? token;
    for (var page = 0; page < 3; page++) {
      final uri = Uri.parse('${AppConfig.llmBaseUrl}/models').replace(queryParameters: {
        'pageSize': '1000', if (token != null) 'pageToken': token,
      });
      final data = await _send((client) => client.get(uri, headers: {'x-goog-api-key': key}), timeout: timeout());
      final raw = data['models'];
      if (raw is List) {
        for (final model in raw.whereType<Map>()) {
          final name = model['name'];
          final methods = model['supportedGenerationMethods'];
          if (name is! String || methods is! List || !methods.contains('generateContent')) continue;
          final id = name.replaceFirst(RegExp(r'^models/'), '');
          if (!RegExp(r'^gemini-[a-zA-Z0-9._-]*flash[a-zA-Z0-9._-]*$').hasMatch(id)) continue;
          if (RegExp(r'image|audio|tts|live|robotics|computer-use').hasMatch(id)) continue;
          names.add(id);
        }
      }
      token = data['nextPageToken'] is String ? data['nextPageToken'] as String : null;
      if (token == null || token.isEmpty) break;
    }
    final sorted = names.toList()..sort((a, b) {
      int score(String m) => (m.contains('lite') ? 0 : 2) + (m.contains('preview') || m.contains('exp') ? 1 : 0);
      final byType = score(a).compareTo(score(b));
      return byType == 0 ? b.compareTo(a) : byType;
    });
    return sorted;
  }

  static Future<String> _completeWith(String model, String key, String system,
      List<Map<String, String>> messages, bool json, {required Duration timeout}) async {
    final uri = Uri.parse('${AppConfig.llmBaseUrl}/models/$model:generateContent');
    final data = await _send((client) => client.post(uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
      body: jsonEncode({
        'systemInstruction': {'parts': [{'text': system}]},
        'contents': [for (final m in messages)
          if ((m['content'] ?? '').trim().isNotEmpty) {
            'role': m['role'] == 'assistant' ? 'model' : 'user',
            'parts': [{'text': m['content']}],
          },
        ],
        if (json) 'generationConfig': {'responseMimeType': 'application/json'},
      }),
    ), timeout: timeout);
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty && candidates.first is Map) {
      final content = (candidates.first as Map)['content'];
      if (content is Map && content['parts'] is List) {
        final out = (content['parts'] as List).whereType<Map>()
            .where((p) => p['thought'] != true && p['text'] is String)
            .map((p) => p['text'] as String).join().trim();
        if (out.isNotEmpty) return out;
      }
    }
    throw LlmException('Gemini nie zwróciło odpowiedzi tekstowej. Zapytanie mogło zostać zablokowane lub przerwane.');
  }
}
