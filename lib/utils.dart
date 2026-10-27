const List<String> kWeekDays = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'Sb', 'Nd'];

const List<String> kMonths = [
  'Styczeń',
  'Luty',
  'Marzec',
  'Kwiecień',
  'Maj',
  'Czerwiec',
  'Lipiec',
  'Sierpień',
  'Wrzesień',
  'Październik',
  'Listopad',
  'Grudzień',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Data lokalna w formacie RRRR-MM-DD.
String dateIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String todayIso() => dateIso(DateTime.now());

/// Pierwsze 10 znaków (RRRR-MM-DD) z daty/czasu ISO.
String first10(String s) => s.length >= 10 ? s.substring(0, 10) : s;

String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

/// Polska nazwa intensywności.
String intensityLabel(String i) {
  if (i == 'low') return 'niska';
  if (i == 'medium') return 'średnia';
  if (i == 'high') return 'wysoka';
  return i;
}

/// Krótki opis treningu: "45 min · intensywność średnia".
String trainingMeta(int durationMin, String intensity) => <String>[
      if (durationMin > 0) '$durationMin min',
      if (intensity.isNotEmpty) 'intensywność ${intensityLabel(intensity)}',
    ].join(' · ');

/// Polish label for the diary streak counter.
String streakDayLabel(int count) => '$count ${count == 1 ? 'dzień' : 'dni'}';
