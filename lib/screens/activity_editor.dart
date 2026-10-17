import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'add_event_screen.dart';
import 'log_match_screen.dart';
import 'log_session_screen.dart';

/// Wspólna ścieżka kalendarza, szczegółów i treningów klubowych.
Future<Widget> activityEditor(EventItem event, {bool complete = false}) async {
  if (event.source == 'trainings' && event.sourceId.isNotEmpty) {
    final training = await Api.getTraining(event.sourceId);
    if (training == null) {
      throw StateError('Nie znaleziono powiązanego treningu. Odśwież kalendarz.');
    }
    return LogSessionScreen(editing: training, kind: training.kind);
  }
  if (event.source == 'matches' && event.sourceId.isNotEmpty) {
    final match = await Api.getMatch(event.sourceId);
    if (match == null) {
      throw StateError('Nie znaleziono powiązanego meczu. Odśwież kalendarz.');
    }
    return LogMatchScreen(editing: match);
  }
  if (event.done && event.type != 'note') {
    throw StateError('Brak powiązania z dziennikiem. Odśwież kalendarz.');
  }
  if (complete && event.type == 'match') {
    return LogMatchScreen(completingEvent: event);
  }
  if (complete && (event.type == 'training' || event.type == 'club_training')) {
    return LogSessionScreen(completingEvent: event, kind: event.type);
  }
  return AddEventScreen(editing: event, initialType: event.type);
}
