import '../utils.dart';

/// Liczba treningów z danym obszarem. Samoocena nie zmienia aktywności.
class SkillRadarService {
  static const Map<String, String> focusToAxis = {
    'Prowadzenie': 'Technika', 'Strzał': 'Strzał', 'Decyzyjność': 'Taktyka',
    'Siła': 'Motoryka', 'Mentalność': 'Mentalność', 'Gierka': 'Taktyka',
    'Podania': 'Technika', 'Przyjęcie': 'Technika', 'Odbiór': 'Taktyka',
    'Gra bez piłki': 'Taktyka', 'Fazy przejściowe': 'Taktyka', 'Szybkość': 'Motoryka',
  };
  static double ratingWeight(dynamic rating) => 1.0;
  static const axes = ['Technika', 'Strzał', 'Taktyka', 'Motoryka', 'Mentalność'];
  static List<String> focuses(Map<String, dynamic> entry) {
    final raw = entry['focuses'];
    return (raw is List && raw.isNotEmpty ? raw.map((e) => e.toString())
      : (entry['focus'] ?? '').toString().split(','))
      .map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  }
  static Map<String, int> areas(List<Map<String, dynamic>> trainings) {
    final counts = <String, int>{for (final k in focusToAxis.keys) k: 0};
    for (final t in trainings) {
      if (t['kind'] == 'recovery') continue;
      for (final focus in focuses(t)) { counts[focus] = (counts[focus] ?? 0) + 1; }
    }
    return counts;
  }
  static Map<String, int> calculate(List<Map<String, dynamic>> trainings,
      List<Map<String, dynamic>> matches, {String? since}) {
    final counts = <String, int>{for (final a in axes) a: 0};
    for (final t in trainings) {
      if (t['kind'] == 'recovery') continue;
      if (since != null && first10((t['date'] ?? '').toString()).compareTo(since) < 0) continue;
      final marked = focuses(t).map((f) => focusToAxis[f]).whereType<String>().toSet();
      for (final axis in marked) { counts[axis] = counts[axis]! + 1; }
    }
    return counts;
  }
}
