import '../utils.dart';

/// Bieżąca seria unikalnych dni wykonanych treningów i meczów.
class StreakService {
  /// Bieżąca seria kończy się dziś lub wczoraj. Starsza seria wygasa.
  ///
  /// Każda data jest liczona raz (również gdy jest kilka treningów dziennie).
  /// Przyszłe daty nie mogą sztucznie podnosić serii.
  static int calculate(Iterable<String> dates, {DateTime? asOf}) {
    final reference = asOf ?? DateTime.now();
    final today = dateIso(DateTime(reference.year, reference.month, reference.day));
    final days = <String>{};
    for (final value in dates) {
      final iso = first10(value);
      final date = DateTime.tryParse(iso);
      if (date == null || dateIso(date) != iso || iso.compareTo(today) > 0) {
        continue;
      }
      days.add(iso);
    }
    if (days.isEmpty) return 0;

    final yesterday = dateIso(DateTime(reference.year, reference.month, reference.day - 1));
    final latest = days.contains(today) ? today : yesterday;
    if (!days.contains(latest)) return 0;
    final lastDay = DateTime.parse(latest);
    var count = 0;
    for (var offset = 0; offset < days.length; offset++) {
      final day = dateIso(DateTime(lastDay.year, lastDay.month, lastDay.day - offset));
      if (!days.contains(day)) break;
      count++;
    }
    return count;
  }
}
