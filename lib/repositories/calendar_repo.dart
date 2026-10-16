part of '../api.dart';

/// Wydzielona implementacja CalendarRepo. Publiczny interfejs pozostaje w Api.
class CalendarRepo {
  static Future<void> synchronizeCalendar() async {
    await LocalDb.synchronized<void>(() async {
        // Uzupełnia kalendarz o treningi i mecze zapisane wcześniej
        // w dzienniku (zanim powstało powiązanie z kalendarzem).
        final events = await LocalDb.list('events');
        final linked = events.map((e) => _s(e['source_id'])).toSet();
        final hiddenDoc = await LocalDb.getDoc('hidden_calendar_links');
        final hidden = (hiddenDoc?['ids'] as List?)?.map(_s).toSet() ?? <String>{};
        var changed = false;
        for (final t in await LocalDb.list('trainings')) {
          if (!linked.contains(_s(t['id'])) && !hidden.contains(_s(t['id']))) {
            events.add(Api._eventForTraining(t));
            changed = true;
          }
        }
        for (final m in await LocalDb.list('matches')) {
          if (!linked.contains(_s(m['id'])) && !hidden.contains(_s(m['id']))) {
            events.add(Api._eventForMatch(m));
            changed = true;
          }
        }
        if (await Api._syncClubEvents(events)) changed = true;
        if (changed) await LocalDb.saveList('events', events);
    });
  }

  static Future<List<EventItem>> listEvents() async {
    final items = await LocalDb.list('events');
    return _sortedBy(items, 'date').map(EventItem.fromJson).toList();
  }

  static Future<List<EventItem>> eventsForDay(String date) async {
    final all = await Api.listEvents();
    int rank(EventItem e) => e.type == 'note' ? 2 : (e.isPending ? 0 : 1);
    return all.where((e) => first10(e.date) == first10(date)).toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.time.compareTo(b.time);
      });
  }

  static Future<List<EventItem>> todayGoals() async {
    final all = await Api.listEvents();
    final today = todayIso();
    final list = all
        .where(
          (e) => first10(e.date) == today && e.isPending && e.type != 'note',
        )
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  static Future<EventItem> createEvent({
    required String date,
    String time = '', // Brak godziny oznacza wydarzenie bez określonej godziny.
    required String type,
    required String title,
    required String description,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) async {
    _validateActivityDate(date, isPlanned: true);
    final doc = <String, dynamic>{
      ...details,
      'id': LocalDb.newId(),
      'date': date,
      'time': time,
      'type': type,
      'title': title,
      'description': description,
      'planned': type != 'note',
      'done': false,
      'created_at': _nowIso(),
    };
    await LocalDb.synchronized<void>(() async {
      final items = await LocalDb.list('events');
      items.add(doc);
      await LocalDb.saveList('events', items);
    });
    return EventItem.fromJson(doc);
  }

  static Future<EventItem> updateEvent(
    String id, {
    required String date,
    required String time,
    required String title,
    required String description,
    Map<String, dynamic>? details,
  }) {
    _validateActivityDate(date, isPlanned: true);
    return LocalDb.synchronized<EventItem>(() async {
      final items = await LocalDb.list('events');
      final idx = items.indexWhere((e) => e['id'] == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
      final e = items[idx];
      e['date'] = date;
      e['time'] = time;
      e['title'] = title;
      e['description'] = description;
      if (details != null) e.addAll(details);
      await LocalDb.saveList('events', items);
      return EventItem.fromJson(e);
    });
  }

  static Future<EventItem> updatePlannedActivity(
    String id, {
    required String date,
    required String title,
    required String description,
    required Map<String, dynamic> details,
  }) {
    _validateActivityDate(date, isPlanned: true);
    return LocalDb.synchronized<EventItem>(() async {
    final items = await LocalDb.list('events');
    final idx = items.indexWhere((e) => _s(e['id']) == id);
    if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
    final e = items[idx];
    if (e['done'] == true || _s(e['source_id']).isNotEmpty) {
      throw ApiException(409, 'Conflict', 'Completed activity cannot be edited as a plan');
    }
    e.addAll(details);
    e['date'] = date;
    e['title'] = title;
    e['description'] = description;
    e['planned'] = true;
    e['updated_at'] = _nowIso();
    await LocalDb.saveList('events', items);
    return EventItem.fromJson(e);
    });
  }

  static Future<EventItem> toggleEvent(String id, bool done) {
    return LocalDb.synchronized<EventItem>(() async {
      final items = await LocalDb.list('events');
      final idx = items.indexWhere((e) => e['id'] == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
      // Oznaczenie wykonania bez dziennika fałszowałoby statystyki.
      final event = items[idx];
      final linked = _s(event['source_id']).isNotEmpty &&
          (_s(event['source']) == 'trainings' || _s(event['source']) == 'matches');
      if (_s(event['type']) != 'note' && !linked) {
        throw StateError('Najpierw zapisz wykonany trening lub mecz w dzienniku.');
      }
      if (linked && !done) {
        throw StateError('Wykonanego wpisu nie można cofnąć bez usunięcia go z dziennika.');
      }
      items[idx]['done'] = done;
      await LocalDb.saveList('events', items);
      return EventItem.fromJson(items[idx]);
    });
  }

  static Future<void> deleteEvent(String id, {bool deleteJournalEntry = true}) {
    return LocalDb.synchronized<void>(() async {
      final events = await LocalDb.list('events');
      final idx = events.indexWhere((e) => e['id'] == id);
      if (idx < 0) throw ApiException(404, 'Not Found', 'Event not found');
      final source = _s(events[idx]['source']);
      final sourceId = _s(events[idx]['source_id']);
      final isClub = _s(events[idx]['type']) == 'club_training' &&
          (source == 'club' || _s(events[idx]['planned_source']) == 'club');
      final date = first10(_s(events[idx]['date']));
      events.removeAt(idx);
      if (!deleteJournalEntry && sourceId.isNotEmpty &&
          (source == 'trainings' || source == 'matches')) {
        final old = await LocalDb.getDoc('hidden_calendar_links');
        final hidden = (old?['ids'] as List?)?.map(_s).toSet() ?? <String>{};
        hidden.add(sourceId);
        await LocalDb.setDoc('hidden_calendar_links', <String, dynamic>{'ids': hidden.toList()});
      }
      await LocalDb.saveList('events', events);
      if (isClub) {
        // Zapamiętaj, żeby trening klubowy nie wrócił automatycznie.
        final doc = await LocalDb.getDoc('club_skipped');
        final dates = doc?['dates'] is List
            ? (doc!['dates'] as List).map(_s).toSet()
            : <String>{};
        dates.add(date);
        await LocalDb.setDoc('club_skipped', <String, dynamic>{
          'dates': dates.toList(),
        });
      }
      if (deleteJournalEntry && sourceId.isNotEmpty &&
          (source == 'trainings' || source == 'matches')) {
        final items = await LocalDb.list(source);
        items.removeWhere((e) => _s(e['id']) == sourceId);
        await LocalDb.saveList(source, items);
      }
    });
  }
}
