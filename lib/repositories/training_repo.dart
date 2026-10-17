part of '../api.dart';

/// Wydzielona implementacja TrainingRepo. Publiczny interfejs pozostaje w Api.
class TrainingRepo {
  static Future<List<Training>> listTrainings() async {
    final items = await LocalDb.list('trainings');
    return _sortedBy(items, 'date', desc: true).map(Training.fromJson).toList();
  }

  static Future<Training> createTraining({
    required String date,
    required int durationMin,
    required List<String> focuses,
    required String intensity,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
    String kind = 'training',
    String? plannedEventId,
    /// True, gdy zapisujemy przyszły plan (Kalendarz → Dodaj), a nie
    /// wykonaną już aktywność. Dzisiejsze planowane treningi nie są
    /// oznaczane jako wykonane.
    bool isPlanned = false,
  }) async {
    _validateActivityDate(date, isPlanned: isPlanned);
    _check(
      durationMin >= 0 && durationMin <= 600,
      'duration_min must be between 0 and 600',
    );
    _check(rating >= 0 && rating <= 5, 'rating must be between 0 (unrated) and 5');
    _check(focuses.isNotEmpty || kind == 'club_training',
        'focuses must not be empty');
    final doc = <String, dynamic>{
      'id': LocalDb.newId(),
      'date': date,
      'duration_min': durationMin,
      'focus': focuses.join(', '),
      'focuses': focuses,
      'intensity': intensity,
      'rating': rating,
      'went_well': wentWell,
      'to_improve': toImprove,
      'notes': notes,
      'kind': kind == 'club_training' ? 'club_training' : 'training',
      'created_at': _nowIso(),
    };
    if (isPlanned) {
      final planDetails = <String>[
        'Czas: $durationMin min',
        'Obszary: ${focuses.join(', ')}',
        'Intensywność: $intensity',
        if (rating > 0) 'Planowana ocena: $rating/5',
        if (wentWell.trim().isNotEmpty) 'Co było dobrze: $wentWell',
        if (toImprove.trim().isNotEmpty) 'Do poprawy: $toImprove',
        if (notes.trim().isNotEmpty) 'Notatka: $notes',
      ].join('\n');
      await Api.createEvent(
        date: date,
        type: kind,
        title: kind == 'club_training' ? 'Trening klubowy: ${focuses.join(', ')}' : 'Trening: ${focuses.join(', ')}',
        details: <String, dynamic>{'focus': focuses.join(', '), 'focuses': focuses, 'duration_min': durationMin, 'intensity': intensity, 'rating': rating, 'went_well': wentWell, 'to_improve': toImprove, 'notes': notes},
        description: planDetails,
      );
      return Training.fromJson(doc);
    }
    return LocalDb.synchronized<Training>(() async {
      // Sprawdzenie planu PRZED dopisaniem treningu i wewnątrz blokady.
      // Dzięki temu nawet dwa równoczesne zapisy nie tworzą duplikatu.
      List<Map<String, dynamic>>? events;
      var eventIndex = -1;
      if (plannedEventId != null && plannedEventId.isNotEmpty) {
        events = await LocalDb.list('events');
        eventIndex = events.indexWhere((e) => _s(e['id']) == plannedEventId);
        if (eventIndex < 0) {
          throw ApiException(404, 'Not Found',
              'Nie znaleziono zaplanowanego treningu w kalendarzu.');
        }
        final planned = events[eventIndex];
        final linkedId = _s(planned['source_id']);
        if (linkedId.isNotEmpty || planned['done'] == true) {
          if (_s(planned['source']) == 'trainings' && linkedId.isNotEmpty) {
            final saved = await LocalDb.list('trainings');
            for (final item in saved) {
              if (_s(item['id']) == linkedId) {
                return Training.fromJson(item);
              }
            }
          }
          throw ApiException(409, 'Conflict',
              'Ten trening jest już zapisany jako wykonany. Otwórz jego edycję.');
        }
        if (_s(planned['type']) != 'training' &&
            _s(planned['type']) != 'club_training') {
          throw ApiException(409, 'Conflict',
              'Wybrane wydarzenie nie jest treningiem.');
        }
      }
      final items = await LocalDb.list('trainings');
      items.add(doc);
      await LocalDb.saveList('trainings', items);
      final linked = Api._eventForTraining(doc);
      if (events != null) {
        final planned = events[eventIndex];
        events[eventIndex] = <String, dynamic>{
          ...planned,
          ...Api._completedEventFields(linked),
          'done': true,
          'source': 'trainings',
          'source_id': doc['id'],
          'planned_source': _s(planned['source']),
        };
        await LocalDb.saveList('events', events);
      } else {
        await Api._addLinkedEvent(linked);
      }
      return Training.fromJson(doc);
    });
  }

  static Future<Training?> getTraining(String id) async {
    final items = await LocalDb.list('trainings');
    for (final t in items) {
      if (_s(t['id']) == id) return Training.fromJson(t);
    }
    return null;
  }

  static Future<MatchEntry?> getMatch(String id) async {
    final items = await LocalDb.list('matches');
    for (final m in items) {
      if (_s(m['id']) == id) return MatchEntry.fromJson(m);
    }
    return null;
  }

  static Future<Training> updateTraining(
    String id, {
    String? date,
    int? durationMin,
    List<String>? focuses,
    String? intensity,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
  }) {
    if (date != null) _validateActivityDate(date, isPlanned: false);
    if (durationMin != null) {
      _check(durationMin >= 0 && durationMin <= 600,
          'Czas treningu musi wynosić od 0 do 600 minut.');
    }
    _check(rating >= 0 && rating <= 5, 'rating must be between 0 (unrated) and 5');
    return LocalDb.synchronized<Training>(() async {
      final items = await LocalDb.list('trainings');
      final idx = items.indexWhere((t) => _s(t['id']) == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Training not found');
      final t = items[idx];
      if (date != null) t['date'] = date;
      if (durationMin != null) t['duration_min'] = durationMin;
      if (focuses != null) {
        t['focuses'] = focuses;
        t['focus'] = focuses.join(', ');
      }
      if (intensity != null) t['intensity'] = intensity;
      t['rating'] = rating;
      t['went_well'] = wentWell;
      t['to_improve'] = toImprove;
      t['notes'] = notes;
      t['updated_at'] = _nowIso();
      await LocalDb.saveList('trainings', items);
      await Api._refreshLinkedEvents(id, Api._eventForTraining(t));
      return Training.fromJson(t);
    });
  }

  static Future<MatchEntry> updateMatch(
    String id, {
    required String date,
    required String opponent,
    required String result,
    required int minutesPlayed,
    required int goals,
    required int assists,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
  }) {
    _validateActivityDate(date, isPlanned: false);
    _check(minutesPlayed >= 0 && minutesPlayed <= 180,
        'Czas meczu musi wynosić od 0 do 180 minut.');
    _check(goals >= 0 && goals <= 20, 'Liczba goli musi wynosić od 0 do 20.');
    _check(assists >= 0 && assists <= 20,
        'Liczba asyst musi wynosić od 0 do 20.');
    _check(rating >= 0 && rating <= 5, 'rating must be between 0 (unrated) and 5');
    return LocalDb.synchronized<MatchEntry>(() async {
      final items = await LocalDb.list('matches');
      final idx = items.indexWhere((m) => _s(m['id']) == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Match not found');
      final m = items[idx];
      m['date'] = date;
      m['opponent'] = opponent;
      m['result'] = result;
      m['minutes_played'] = minutesPlayed;
      m['goals'] = goals;
      m['assists'] = assists;
      m['rating'] = rating;
      m['went_well'] = wentWell;
      m['to_improve'] = toImprove;
      m['notes'] = notes;
      m['updated_at'] = _nowIso();
      await LocalDb.saveList('matches', items);
      await Api._refreshLinkedEvents(id, Api._eventForMatch(m));
      return MatchEntry.fromJson(m);
    });
  }

  static Future<void> rateClubTraining(
    EventItem e, {
    required List<String> focuses,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
  }) async {
    if (e.source == 'trainings' && e.sourceId.isNotEmpty) {
      final existing = await Api.getTraining(e.sourceId);
      if (existing != null) {
        await Api.updateTraining(
          e.sourceId,
          focuses: focuses,
          rating: rating,
          wentWell: wentWell,
          toImprove: toImprove,
          notes: notes,
        );
        return;
      }
    }
    final profile = await LocalDb.getDoc('profile') ?? <String, dynamic>{};
    final dur = e.durationMin > 0
        ? e.durationMin
        : (_i(profile['club_duration_min']) > 0
            ? _i(profile['club_duration_min'])
            : 90);
    await Api.createTraining(
      date: first10(e.date),
      durationMin: dur,
      focuses: focuses,
      intensity: e.intensity.isNotEmpty ? e.intensity : 'medium',
      rating: rating,
      wentWell: wentWell,
      toImprove: toImprove,
      notes: notes,
      kind: 'club_training',
      plannedEventId: e.id,
    );
  }

  static Future<void> deleteTraining(String id) async {
    await LocalDb.synchronized<void>(() async {
      final items = await LocalDb.list('trainings');
      if (!items.any((e) => e['id'] == id)) throw ApiException(404, 'Not Found', 'Training not found');
      items.removeWhere((e) => e['id'] == id);
      final events = await LocalDb.list('events');
      events.removeWhere((e) => e['source_id'] == id);
      await LocalDb.saveList('trainings', items);
      await LocalDb.saveList('events', events);
    });
  }

  static Future<List<MatchEntry>> listMatches() async {
    final items = await LocalDb.list('matches');
    return _sortedBy(
      items,
      'date',
      desc: true,
    ).map(MatchEntry.fromJson).toList();
  }

  static Future<MatchEntry> createMatch({
    required String date,
    required String opponent,
    required String result,
    required int minutesPlayed,
    required int goals,
    required int assists,
    required int rating,
    required String wentWell,
    required String toImprove,
    required String notes,
    String? plannedEventId,
    /// True, gdy zapisujemy przyszły plan (Kalendarz → Dodaj), a nie
    /// wykonaną już aktywność. Dzisiejsze planowane mecze nie są
    /// oznaczane jako wykonane.
    bool isPlanned = false,
  }) async {
    _validateActivityDate(date, isPlanned: isPlanned);
    _check(
      minutesPlayed >= 0 && minutesPlayed <= 180,
      'minutes_played must be between 0 and 180',
    );
    _check(goals >= 0 && goals <= 20, 'goals must be between 0 and 20');
    _check(assists >= 0 && assists <= 20, 'assists must be between 0 and 20');
    _check(rating >= 0 && rating <= 5, 'rating must be between 0 (unrated) and 5');
    final doc = <String, dynamic>{
      'id': LocalDb.newId(),
      'date': date,
      'opponent': opponent,
      'result': result,
      'minutes_played': minutesPlayed,
      'goals': goals,
      'assists': assists,
      'rating': rating,
      'went_well': wentWell,
      'to_improve': toImprove,
      'notes': notes,
      'created_at': _nowIso(),
    };
    if (isPlanned) {
      final planDetails = <String>[
        'Rywal: $opponent',
        if (result.trim().isNotEmpty) 'Wynik: $result',
        'Minuty: $minutesPlayed',
        'Bramki: $goals',
        'Asysty: $assists',
        if (rating > 0) 'Planowana ocena: $rating/5',
        if (wentWell.trim().isNotEmpty) 'Co było dobrze: $wentWell',
        if (toImprove.trim().isNotEmpty) 'Do poprawy: $toImprove',
        if (notes.trim().isNotEmpty) 'Notatka: $notes',
      ].join('\n');
      await Api.createEvent(
        date: date,
        type: 'match',
        title: opponent.trim().isEmpty ? 'Mecz' : 'Mecz z $opponent',
        details: <String, dynamic>{'opponent': opponent, 'result': result, 'minutes_played': minutesPlayed, 'goals': goals, 'assists': assists, 'rating': rating, 'went_well': wentWell, 'to_improve': toImprove, 'notes': notes},
        description: planDetails,
      );
      return MatchEntry.fromJson(doc);
    }
    return LocalDb.synchronized<MatchEntry>(() async {
      List<Map<String, dynamic>>? events;
      var eventIndex = -1;
      if (plannedEventId != null && plannedEventId.isNotEmpty) {
        events = await LocalDb.list('events');
        eventIndex = events.indexWhere((e) => _s(e['id']) == plannedEventId);
        if (eventIndex < 0) {
          throw ApiException(404, 'Not Found',
              'Nie znaleziono zaplanowanego meczu w kalendarzu.');
        }
        final planned = events[eventIndex];
        final linkedId = _s(planned['source_id']);
        if (linkedId.isNotEmpty || planned['done'] == true) {
          if (_s(planned['source']) == 'matches' && linkedId.isNotEmpty) {
            final saved = await LocalDb.list('matches');
            for (final item in saved) {
              if (_s(item['id']) == linkedId) {
                return MatchEntry.fromJson(item);
              }
            }
          }
          throw ApiException(409, 'Conflict',
              'Ten mecz jest już zapisany jako wykonany. Otwórz jego edycję.');
        }
        if (_s(planned['type']) != 'match') {
          throw ApiException(409, 'Conflict',
              'Wybrane wydarzenie nie jest meczem.');
        }
      }
      final items = await LocalDb.list('matches');
      items.add(doc);
      await LocalDb.saveList('matches', items);
      final linked = Api._eventForMatch(doc);
      if (events != null) {
        final planned = events[eventIndex];
        events[eventIndex] = <String, dynamic>{
          ...planned,
          ...Api._completedEventFields(linked),
          'done': true,
          'source': 'matches',
          'source_id': doc['id'],
          'planned_source': _s(planned['source']),
        };
        await LocalDb.saveList('events', events);
      } else {
        await Api._addLinkedEvent(linked);
      }
      return MatchEntry.fromJson(doc);
    });
  }

  static Future<void> deleteMatch(String id) async {
    await Api._deleteFrom('matches', id, 'Match not found');
    await Api._deleteLinkedEvents(id);
  }
}
