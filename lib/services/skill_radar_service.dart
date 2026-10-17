import '../utils.dart';

/// Agreguje obszary umiejętności z wykonanych aktywności.
class SkillRadarService {
  static const Map<String, String> focusToAxis = <String, String>{
    'Prowadzenie': 'Technika',
    'Strzał': 'Strzał',
    'Decyzyjność': 'Taktyka',
    'Siła': 'Motoryka',
    'Mentalność': 'Mentalność',
  };
  static const List<String> axes = <String>['Technika', 'Strzał', 'Taktyka', 'Motoryka', 'Mentalność'];

  static double ratingWeight(dynamic r) {
    final v = (r is num ? r.toInt() : 3).clamp(1, 5);
    return 0.5 + (v - 1) * 0.175;
  }

  static Map<String, int> calculate(List<Map<String, dynamic>> trainings, List<Map<String, dynamic>> matches, {String? since}) {
    String str(dynamic v) => v == null ? '' : v.toString();
    String day(Map<String, dynamic> e) => first10(str(e['date']));
    final weights = <String, double>{for (final a in axes) a: 0.0};
    for (final t in trainings) {
      if (since != null && day(t).compareTo(since) < 0) continue;
      final raw = t['focuses'];
      final focuses = raw is List && raw.isNotEmpty ? raw.map(str).toList() : str(t['focus']).split(',').map((e) => e.trim()).toList();
      final share = focuses.isEmpty ? 0.0 : 1.0 / focuses.length;
      for (final focus in focuses) {
        final axis = focusToAxis[focus];
        if (axis != null) weights[axis] = weights[axis]! + ratingWeight(t['rating']) * share;
      }
    }
    for (final m in matches) {
      if (since != null && day(m).compareTo(since) < 0) continue;
      weights['Mentalność'] = weights['Mentalność']! + ratingWeight(m['rating']) * 0.5;
    }
    return <String, int>{for (final e in weights.entries) e.key: ((e.value / 10) * 100).toInt().clamp(0, 100).toInt()};
  }
}

