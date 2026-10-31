/// Opcjonalne statystyki: null oznacza brak obserwacji, 0 jest świadomym wynikiem.
class MatchStats {
  static const labels = <String, String>{
    'shots': 'Strzały', 'shots_on_target': 'Strzały celne',
    'passes_completed': 'Celne podania', 'passes_attempted': 'Wszystkie podania',
    'tackles': 'Odbiory', 'interceptions': 'Przechwyty', 'successful_dribbles': 'Udane dryblingi',
  };
  static int? value(dynamic raw) => raw is num && raw.isFinite && raw % 1 == 0 ? raw.toInt() : null;
  static String? error(Map<String, dynamic> stats) {
    for (final entry in labels.entries) {
      final raw = stats[entry.key];
      if (raw != null && (value(raw) == null || value(raw)! < 0 || value(raw)! > 2000)) {
        return '${entry.value}: podaj liczbę całkowitą od 0 do 2000 albo pozostaw puste.';
      }
    }
    for (final pair in [['shots_on_target','shots'],['passes_completed','passes_attempted']]) {
      final part = value(stats[pair[0]]), total = value(stats[pair[1]]);
      if (part != null && total != null && part > total) return '${labels[pair[0]]} nie mogą przekraczać pola „${labels[pair[1]]}”.';
    }
    return null;
  }
  static Map<String, int?> fromJson(dynamic raw) {
    final map = raw is Map ? raw : const {};
    return {for (final key in labels.keys) key: value(map[key])};
  }
}
