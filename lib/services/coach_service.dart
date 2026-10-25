part of '../api.dart';

/// Wydzielona implementacja CoachService. Publiczny interfejs pozostaje w Api.
class CoachService {
  static Future<WeakSpotsPayload?> getWeakSpots() async {
    final doc = await LocalDb.getDoc('weak_spots');
    if (doc == null) return null;
    return WeakSpotsPayload.fromJson(doc);
  }

  static Future<WeakSpotsPayload> analyzeWeakSpots() async {
    final trainings = await LocalDb.list('trainings');
    final matches = await LocalDb.list('matches');

    final notes = <String>[];
    for (final t in trainings) {
      final n = _s(t['to_improve']).trim();
      if (n.isNotEmpty) {
        final club = _s(t['kind']) == 'club_training';
        notes.add('[${club ? 'Trening klubowy' : 'Trening'} '
            '${first10(_s(t['date']))}'
            '${_s(t['focus']).isNotEmpty ? ' · ${_s(t['focus'])}' : ''}] $n');
      }
    }
    for (final m in matches) {
      final n = _s(m['to_improve']).trim();
      if (n.isNotEmpty) {
        notes.add(
          '[Mecz ${first10(_s(m['date']))} vs ${_s(m['opponent'])}] $n',
        );
      }
    }

    if (notes.isEmpty) {
      final empty = <String, dynamic>{
        'weak_spots': <Map<String, dynamic>>[],
        'generated_at': _nowIso(),
        'note_count': 0,
        'source': 'offline',
        'fallback_reason': 'Brak notatek „Co trzeba poprawić?” do analizy.',
      };
      await LocalDb.setDoc('weak_spots', empty);
      CoachRuntime.record('offline', 'analiza', _s(empty['generated_at']), notice: _s(empty['fallback_reason']));
      return WeakSpotsPayload.fromJson(empty);
    }

    var spots = <Map<String, dynamic>>[];
    var source = 'offline';
    var notice = Llm.enabled ? '' : Llm.offlineReason;

    var onlineAnalysis = false;
    if (Llm.enabled) {
      try {
        final last =
            notes.length > 50 ? notes.sublist(notes.length - 50) : notes;
        final prompt =
            "Przeanalizuj poniższe notatki zawodnika z pola 'Co trzeba poprawić?' "
            'i wskaż 2-5 powtarzających się słabych punktów:\n\n'
            '${last.map((n) => '- $n').join('\n')}';
        final raw = await Llm.complete(
          json: true,
          system: kWeakSpotsSystem,
          messages: <Map<String, String>>[
            <String, String>{'role': 'user', 'content': prompt},
          ],
        );
        final parsed = _extractJsonObject(raw);
        final items = parsed?['weak_spots'];
        if (items is List) {
          for (final it in items.take(5)) {
            if (it is! Map) continue;
            final insight = _s(it['insight']).trim();
            if (insight.isEmpty) continue;
            var priority = _s(it['priority']);
            if (priority != 'low' &&
                priority != 'medium' &&
                priority != 'high') {
              priority = 'medium';
            }
            spots.add(<String, dynamic>{
              'area': _orDefault(it['area'], 'Inne'),
              'insight': insight,
              'priority': priority,
            });
          }
        }
        if (items is! List || (items.isNotEmpty && spots.isEmpty)) {
          throw LlmException('Gemini zwróciło nieprawidłowy format analizy. Użyto analizy offline.');
        }
        onlineAnalysis = true;
        source = 'online';
      } catch (error) {
        notice = Llm.explain(error);
        spots = <Map<String, dynamic>>[];
      }
    }

    if (!onlineAnalysis) {
      // Wersja offline - zliczanie słów kluczowych.
      final tally = <String, int>{};
      void bump(String k) => tally[k] = (tally[k] ?? 0) + 1;
      for (final n in notes) {
        final l = n.toLowerCase();
        if (l.contains('strzał') || l.contains('strzelić')) bump('Strzał');
        if (l.contains('podani') ||
            l.contains('przyj') ||
            l.contains('prowadz')) {
          bump('Technika');
        }
        if (l.contains('decyzj') ||
            l.contains('ustaw') ||
            l.contains('pole widzenia')) {
          bump('Taktyka');
        }
        if (l.contains('sił') || l.contains('wytrzym') || l.contains('szybk')) {
          bump('Motoryka');
        }
        if (l.contains('koncentr') ||
            l.contains('ner') ||
            l.contains('pewno')) {
          bump('Mentalność');
        }
      }
      final order = tally.keys.toList();
      final sorted = List<String>.from(order)
        ..sort((a, b) {
          final c = tally[b]!.compareTo(tally[a]!);
          return c != 0 ? c : order.indexOf(a).compareTo(order.indexOf(b));
        });
      for (final area in sorted.take(5)) {
        final count = tally[area]!;
        spots.add(<String, dynamic>{
          'area': area,
          'insight':
              'Notatki wskazują na powtarzający się temat: ${area.toLowerCase()} ($count wpisów). Dołóż ćwiczenia rozwijające ten obszar.',
          'priority': count < 3 ? 'medium' : 'high',
        });
      }
    }

    final payload = <String, dynamic>{
      'weak_spots': spots,
      'generated_at': _nowIso(),
      'note_count': notes.length,
      'source': source,
      'fallback_reason': notice,
    };
    await LocalDb.setDoc('weak_spots', payload);
    CoachRuntime.record(source, 'analiza', _s(payload['generated_at']), notice: notice);
    return WeakSpotsPayload.fromJson(payload);
  }

  static Future<Profile> getProfile() async {
    final doc = await LocalDb.getDoc('profile');
    if (doc == null) {
      return Profile.fromJson(<String, dynamic>{
        'name': '',
        'age': null,
        'position': '',
        'dominant_foot': '',
        'club': '',
        'jersey_number': null,
        'season_goal': '',
        'theme': 'dark',
        'updated_at': _nowIso(),
      });
    }
    return Profile.fromJson(doc);
  }

  static Future<Profile> updateProfile(Profile p) async {
    _check(p.age == null || (p.age! >= 8 && p.age! <= 21),
        'Wiek zawodnika powinien mieścić się w przedziale 8–21 lat.');
    final data = p.toJson();
    data['updated_at'] = _nowIso();
    await LocalDb.setDoc('profile', data);
    await Api.synchronizeCalendar();
    return Profile.fromJson(data);
  }

  static Future<List<Drill>> drills() async {
    final library = await OfflineCoach.exercises();
    return <Drill>[
      ...kDrills.map(Drill.fromJson),
      for (final e in library.where((e) => e['import_package'] == 'baza_dziennika_pilkarza_v1'))
        Drill.fromJson({
          'id': e['id'], 'title': e['title'], 'focus': e['journal_focus'],
          'duration_min': e['duration_min'], 'intensity': e['intensity'],
          'source': 'Ćwiczenie z bazy offline',
          'description': <String>[
            'Cel: ${e['goal']}',
            'Uczestnicy: ${e['participants_max']}.',
            'Sprzęt: ${(e['equipment'] as List).join(', ')}.',
            'Przestrzeń: ${e['space']}.',
            'Wiek: od ${e['min_age']} lat.',
            if (e['source_intensity'] == 'none') 'Zadanie refleksyjne, bez obciążenia fizycznego.',
            '${e['age_policy']}',
            '${e['limitations']}',
            'Dawkowanie i dopasowanie zadania omów z trenerem.',
          ].join('\n\n'),
          'steps': e['steps'],
        }),
    ];
  }

  static Future<String> motivation() async {
    final now = DateTime.now();
    final ordinal = DateTime.utc(
          now.year,
          now.month,
          now.day,
        ).difference(DateTime.utc(1, 1, 1)).inDays +
        1;
    return kMotivations[ordinal % kMotivations.length];
  }

  static Future<String> chat(String sessionId, String message) async {
    final all = await LocalDb.list('chat_messages');
    final session = all.where((m) => m['session_id'] == sessionId).toList();

    String reply;
    var source = 'offline';
    var notice = Llm.enabled ? '' : Llm.offlineReason;
    if (Llm.enabled) {
      final recent =
          session.length > 20 ? session.sublist(session.length - 20) : session;
      final context = await Api._playerContext();
      try {
        reply = await Llm.complete(
          system: '$kCoachSystem\n\n$context',
          messages: <Map<String, String>>[
            for (final m in recent)
              <String, String>{
                'role': _s(m['role']),
                'content': _s(m['content']),
              },
            <String, String>{'role': 'user', 'content': message},
          ],
        );
        source = 'online';
      } catch (error) {
        notice = Llm.explain(error);
        reply = await OfflineCoach.reply(message);
      }
    } else {
      reply = await OfflineCoach.reply(message);
    }

    final generatedAt = _nowIso();
    await LocalDb.synchronized<void>(() async {
      final items = await LocalDb.list('chat_messages');
      items.add(<String, dynamic>{
        'id': LocalDb.newId(),
        'session_id': sessionId,
        'role': 'user',
        'content': message,
        'created_at': _nowIso(),
      });
      items.add(<String, dynamic>{
        'id': LocalDb.newId(),
        'session_id': sessionId,
        'role': 'assistant',
        'content': reply,
        'source': source,
        'fallback_reason': notice,
        'created_at': generatedAt,
      });
      final trimmed =
          items.length > 200 ? items.sublist(items.length - 200) : items;
      await LocalDb.saveList('chat_messages', trimmed);
    });
    CoachRuntime.record(source, 'rozmowa', generatedAt, notice: notice);
    return reply;
  }
}
