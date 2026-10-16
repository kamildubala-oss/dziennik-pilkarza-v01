import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'llm_settings.dart';

class LlmException implements Exception {
  LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Klient modelu językowego Google Gemini (natywne API `generateContent`).
/// Klucze w formacie `AQ.` wymagają nagłówka `x-goog-api-key`.
/// Klucz: wyłącznie własny, podany w ustawieniach.
/// Gdy nie ma żadnego, aplikacja używa trybu offline.
class Llm {
  Llm._();

  static bool get enabled => LlmSettings.allowNetwork;

  /// Sprawdza klucz API (lista modeli - nie zużywa limitu zapytań).
  /// Zwraca null, gdy klucz działa; w przeciwnym razie opis problemu.
  /// [networkError] = true, gdy nie udało się połączyć.
  static Future<({String? error, bool networkError})> testKey(
      String key) async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.llmBaseUrl}/models?pageSize=1'),
        headers: <String, String>{'x-goog-api-key': key.trim()},
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return (error: null, networkError: false);
      }
      if (res.statusCode == 400 ||
          res.statusCode == 401 ||
          res.statusCode == 403) {
        return (
          error: 'Klucz jest nieprawidłowy lub nie ma dostępu do Gemini API.',
          networkError: false,
        );
      }
      if (res.statusCode == 429) {
        return (
          error:
              'Klucz działa, ale przekroczono limit zapytań. Spróbuj później.',
          networkError: false,
        );
      }
      return (
        error: 'Serwer Google zwrócił błąd ${res.statusCode}.',
        networkError: true,
      );
    } catch (_) {
      return (
        error: 'Nie udało się połączyć z serwerem Google. Sprawdź internet.',
        networkError: true,
      );
    }
  }

  /// [fast] - najpierw szybszy model (np. plan tygodnia).
  /// [json] - wymusza odpowiedź w formacie JSON.
  /// Gdy pierwszy model jest przeciążony / nie odpowiada, próbuje drugiego.
  static Future<String> complete({
    required String system,
    required List<Map<String, String>> messages,
    bool fast = false,
    bool json = false,
  }) async {
    final models = fast
        ? <String>[AppConfig.llmFastModel, AppConfig.llmModel]
        : <String>[AppConfig.llmModel, AppConfig.llmFastModel];
    for (final model in models) {
      try {
        return await _completeWith(model, system, messages, json);
      } catch (_) {
        // Spróbuj alternatywnego modelu.
      }
    }
    throw LlmException('Nie udało się uzyskać odpowiedzi trenera AI. Sprawdź połączenie i spróbuj ponownie.');
  }

  static Future<String> _completeWith(
    String model,
    String system,
    List<Map<String, String>> messages,
    bool json,
  ) async {
    final uri = Uri.parse(
      '${AppConfig.llmBaseUrl}/models/$model:generateContent',
    );

    final contents = <Map<String, dynamic>>[
      for (final m in messages)
        if ((m['content'] ?? '').trim().isNotEmpty)
          <String, dynamic>{
            'role': m['role'] == 'assistant' ? 'model' : 'user',
            'parts': <Map<String, String>>[
              <String, String>{'text': m['content']!},
            ],
          },
    ];

    final res = await http
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'x-goog-api-key': LlmSettings.activeKey,
          },
          body: jsonEncode(<String, dynamic>{
            'systemInstruction': <String, dynamic>{
              'parts': <Map<String, String>>[
                <String, String>{'text': system},
              ],
            },
            'contents': contents,
            if (json)
              'generationConfig': <String, dynamic>{
                'responseMimeType': 'application/json',
              },
          }),
        )
        .timeout(const Duration(seconds: 25));

    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw LlmException('${res.statusCode} ${res.reasonPhrase ?? ''}: $text');
    }
    final data = jsonDecode(text) as Map<String, dynamic>;
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final content = (candidates.first as Map<String, dynamic>)['content'];
      if (content is Map && content['parts'] is List) {
        final out = (content['parts'] as List)
            .whereType<Map>()
            .where((p) => p['thought'] != true && p['text'] != null)
            .map((p) => p['text'].toString())
            .join();
        if (out.trim().isNotEmpty) return out.trim();
      }
    }
    throw LlmException('Pusta odpowiedź modelu');
  }
}
