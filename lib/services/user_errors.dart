import '../api.dart';

/// Przyjazne błędy dla młodego zawodnika: nigdy nie pokazujemy kodów HTTP
/// ani nazw wewnętrznych pól z API.
String friendlyError(Object error) {
  if (error is ApiException) {
    final body = error.body;
    final lower = body.toLowerCase();
    if (lower.contains('duration_min')) {
      return 'Czas treningu musi wynosić od 0 do 600 minut.';
    }
    if (lower.contains('minutes_played')) {
      return 'Czas meczu musi wynosić od 0 do 180 minut.';
    }
    if (lower.contains('goals')) {
      return 'Liczba goli musi wynosić od 0 do 20.';
    }
    if (lower.contains('assists')) {
      return 'Liczba asyst musi wynosić od 0 do 20.';
    }
    if (lower.contains('rating')) {
      return 'Wybierz ocenę od 1 do 5.';
    }
    if (lower.contains('focuses')) {
      return 'Wybierz co najmniej jeden obszar treningu.';
    }
    if (error.statusCode == 409) {
      return body.toLowerCase().contains('już') ? body :
          'Ta aktywność została już zapisana. Otwórz jej edycję.';
    }
    if (error.statusCode == 404) {
      return 'Nie znaleziono tego wpisu. Odśwież ekran i spróbuj ponownie.';
    }
    if (body.contains('Nie można') || body.contains('Nieprawidł') ||
        body.contains('Podaj') || body.contains('Czas') ||
        body.contains('Brak ') || body.contains('Wybierz')) {
      return body;
    }
    return error.statusCode == 400 || error.statusCode == 422
        ? 'Sprawdź podane dane i spróbuj ponownie.'
        : 'Nie udało się zapisać zmian. Spróbuj ponownie.';
  }
  if (error is FormatException) {
    return 'Nie można odczytać danych. Sprawdź wpis lub przywróć kopię zapasową.';
  }
  if (error is StateError) {
    return 'Nie można teraz wykonać tej operacji. Odśwież ekran.';
  }
  return 'Wystąpił problem z zapisem. Spróbuj ponownie.';
}

/// Sprawdzenie całkowitej liczby bez cichego zastępowania błędu zerem.
/// Przydatne do walidacji na bieżąco bez żądania zapisu.
String? numberFieldError(String input, String label, int min, int max) {
  final text = input.trim();
  if (text.isEmpty) return 'Wpisz liczbę w polu „$label”.';
  if (!RegExp(r'^\d+$').hasMatch(text)) {
    return 'W polu „$label” wpisz tylko liczbę.';
  }
  final value = int.tryParse(text);
  if (value == null || value < min || value > max) {
    return 'W polu „$label” wpisz liczbę od $min do $max.';
  }
  return null;
}
