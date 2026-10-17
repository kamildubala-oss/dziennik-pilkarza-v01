import '../utils.dart';

/// Liczba wykonanych treningów obejmujących obszar, bez oceny umiejętności.
/// Jeden trening może obejmować kilka obszarów. Mecze nie są automatycznie
/// przypisywane do mentalności. Parametr matches zachowuje zgodność API.
class SkillRadarService {
  static const Map<String, String> focusToAxis = {
    'Prowadzenie': 'Technika',
    'Technika': 'Technika',
    'Strzał': 'Strzał',
    'Decyzyjność': 'Taktyka',
    'Taktyka': 'Taktyka',
    'Siła': 'Motoryka',
    'Motoryka': 'Motoryka',
    'Mentalność': 'Mentalność',
  };
  static const List<String> axes = [
    'Technika',
    'Strzał',
    'Taktyka',
    'Motoryka',
    'Mentalność',
  ];
  static Map<String, int> calculate(
    List<Map<String, dynamic>> trainings,
    List<Map<String, dynamic>> matches, {
    String? since,
    String? until,
  }) {
    final counts = {for (final axis in axes) axis: 0};
    for (final t in trainings) {
      final date = first10(t['date']?.toString() ?? '');
      if (since != null && date.compareTo(since) < 0) continue;
      if (until != null && date.compareTo(until) > 0) continue;
      final raw = t['focuses'];
      final focuses = raw is List && raw.isNotEmpty
          ? raw.map((f) => f.toString())
          : (t['focus']?.toString() ?? '').split(',').map((f) => f.trim());
      final areas = focuses
          .map((f) => focusToAxis[f])
          .whereType<String>()
          .toSet();
      for (final area in areas) {
        counts[area] = counts[area]! + 1;
      }
    }
    return counts;
  }
}
