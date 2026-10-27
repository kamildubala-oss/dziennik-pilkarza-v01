// Treści trenera: ćwiczenia, motywacje, polecenia dla AI i odpowiedzi offline.
// Port 1:1 z backendu (server.py).

const List<Map<String, dynamic>> kDrills = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'drill-prowadzenie',
    'title': 'Prowadzenie piłki',
    'focus': 'Prowadzenie',
    'duration_min': 20,
    'intensity': 'medium',
    'source': 'Ćwiczenie autorskie',
    'description':
        'Slalom między pachołkami ze zmianą tempa i kierunku. 6 serii x 2 powtórzenia.',
    'steps': <String>[
      'Rozgrzewka: 5 min truchtu i krążeń.',
      'Slalom pomiędzy 8 pachołkami ustawionych co 1,5 m – wewnętrznym podbiciem.',
      'Powtórka slalomu zewnętrznym podbiciem.',
      'Dodaj zmianę kierunku co 2 pachołek.',
      'Chłodzenie i rozciąganie.',
    ],
  },
  <String, dynamic>{
    'id': 'drill-strzal',
    'title': 'Celność strzału',
    'focus': 'Strzał',
    'duration_min': 25,
    'intensity': 'high',
    'source': 'Ćwiczenie autorskie',
    'description': 'Oddawaj celne strzały z krótkiego prowadzenia, zmieniając nogę i wybrany sektor bramki.',
    'steps': <String>[
      'Ustaw dwa cele przy ziemi w zamocowanej bramce i sprawdź, czy nikt nie znajduje się za nią.',
      'Z odległości pozwalającej uderzać bez używania maksymalnej siły wykonaj kilka spokojnych strzałów prawą nogą do lewego celu.',
      'Zmień nogę i skieruj kolejne piłki do prawego celu; przed uderzeniem ustaw stopę podporową obok piłki.',
      'Dodaj prowadzenie z 3–4 m: ostatnim kontaktem przygotuj piłkę do strzału i uderz bez zatrzymywania jej podeszwą.',
      'Po kilku próbach odpocznij i porównaj celność obu nóg; wróć bliżej bramki, jeśli piłki stale mijają cel.',
    ],
  },
  <String, dynamic>{
    'id': 'drill-decyzyjnosc',
    'title': 'Decyzyjność 1v1',
    'focus': 'Decyzyjność',
    'duration_min': 20,
    'intensity': 'high',
    'source': 'Ćwiczenie autorskie',
    'description': 'W pojedynku z partnerem wybieraj wolną bramkę i zmieniaj kierunek, gdy obrońca zasłoni pierwsze wyjście.',
    'steps': <String>[
      'Zaznacz pole około 6 × 6 m i dwie bramki na końcowej linii; partner ustawia się między nimi.',
      'Rozpocznij z przeciwnego końca, prowadząc piłkę krótkimi kontaktami w kierunku partnera.',
      'Przed zbliżeniem do obrońcy spójrz na obie bramki i zaznacz zwód w stronę jednego wyjścia.',
      'Popchnij piłkę w stronę wolnej bramki i przeprowadź ją przez linię pod kontrolą.',
      'Po bramce lub stracie wróć na start i zamieńcie role; pierwsze próby wykonajcie z lekką obroną, bez wślizgów.',
    ],
  },
  <String, dynamic>{
    'id': 'drill-sila',
    'title': 'Siła i stabilizacja',
    'focus': 'Siła',
    'duration_min': 15,
    'intensity': 'medium',
    'source': 'Ćwiczenie autorskie',
    'description': 'Połącz kontrolowany przysiad i wykrok ze stabilizacją tułowia. Pracuj bez dodatkowego obciążenia i bez pośpiechu.',
    'steps': <String>[
      'Rozpocznij od marszu i kilku spokojnych ugięć nóg, sprawdzając, czy ruch jest swobodny i bezbolesny.',
      'Wykonaj 6 powolnych przysiadów: całe stopy na ziemi, kolana w kierunku palców, zejście tylko do wygodnego zakresu.',
      'Po odpoczynku zrób po 4 wykroki w tył na każdą nogę; po każdym wróć do stabilnego stania.',
      'Połóż się na plecach, unieś ugięte nogi i powoli opuszczaj przeciwną rękę oraz nogę; wykonaj po 4 ruchy na stronę bez odrywania pleców.',
      'Odpocznij i oceń jakość ruchu; powtórz obwód tylko przy zachowaniu kontroli, a przy bólu zakończ zadanie.',
    ],
  },
  <String, dynamic>{
    'id': 'drill-mentalnosc',
    'title': 'Mentalność zwycięzcy',
    'focus': 'Mentalność',
    'duration_min': 10,
    'intensity': 'low',
    'source': 'Ćwiczenie autorskie',
    'description': 'Przygotuj jedną konkretną reakcję na trudną sytuację i krótki cel do zastosowania w najbliższym treningu.',
    'steps': <String>[
      'Usiądź wygodnie i wykonaj kilka spokojnych oddechów, bez wstrzymywania powietrza.',
      'Przypomnij sobie jedną udaną akcję i nazwij zachowanie, które w niej pomogło, na przykład spojrzenie przed przyjęciem.',
      'Wyobraź sobie podobną sytuację na następnym treningu: zobacz ruch, pierwszy kontakt i kolejne podanie.',
      'Zapisz jedno zdanie zaczynające się od „Dzisiaj spróbuję…”, odnoszące się do własnego działania, a nie do wyniku.',
      'Po treningu wróć do tego zdania i dopisz jeden przykład wykonania albo sytuację do kolejnej próby.',
    ],
  },
];

const List<String> kMotivations = <String>[
  'Każdy wielki piłkarz zaczynał od pierwszego dotknięcia piłki. Zrób dziś jedno więcej.',
  'Nie liczy się talent – liczy się regularność. Zapisz dziś swój trening.',
  'Technika rodzi się z powtórzeń. 100 strzałów dziennie = sezon różnicy.',
  'Dobry piłkarz podejmuje decyzje przed przyjęciem piłki. Trenuj głowę razem z nogami.',
  'Mentalność jest jak mięsień – trenuj ją tak samo mocno jak strzał.',
];

const List<String> kPolishDays = <String>[
  'Poniedziałek',
  'Wtorek',
  'Środa',
  'Czwartek',
  'Piątek',
  'Sobota',
  'Niedziela',
];

const String kCoachSystem =
    'Jesteś osobistym trenerem młodego piłkarza (10-16 lat). Mówisz WYŁĄCZNIE po polsku. '
    "Twoje wskazówki bazują na autorskiej bibliotece ćwiczeń oraz ogólnych zasadach treningu indywidualnego "
    'oraz programie treningowym IMOPEKSIS. Styl: krótko, konkretnie, motywująco, bez infantylności. '
    'Zawsze odpowiadaj w 3 sekcjach: (1) Krótka motywacja (max 2 zdania), '
    '(2) Co dzisiaj zrobić – lista 3-5 punktów, (3) Na co zwrócić uwagę. '
    'Nie używaj emoji. Nie udzielaj porad medycznych. Jeśli uczeń opisuje ból – kieruj do dorosłego/trenera.';

const String kPlanSystem =
    'Jesteś indywidualnym trenerem piłkarskim. Masz zbudować 7-dniowy plan treningowy dla młodego piłkarza. '
    'Zwróć WYŁĄCZNIE poprawny JSON (bez komentarzy, bez markdown, bez tekstu wokół) o schemacie: '
    '{"days":[{"day_name":"Poniedziałek","focus":"Prowadzenie|Strzał|Decyzyjność|Siła|Mentalność|Odpoczynek|Mecz|Trening klubowy","title":"krótka nazwa","duration_min":30,"intensity":"low|medium|high","description":"max 2 zdania po polsku - cel dnia","steps":["konkretne ćwiczenie z czasem lub liczbą powtórzeń"],"tip":"1 zdanie - na co zwrócić uwagę"}, ...]}'
    ' Lista musi mieć DOKŁADNIE 7 obiektów w kolejności Poniedziałek..Niedziela. '
    'Każdy dzień musi mieć 4-6 kroków w "steps": rozgrzewka, 2-4 ćwiczenia główne '
    '(z czasem, liczbą serii/powtórzeń i potrzebnym sprzętem, np. pachołki, piłka, ściana) '
    'oraz schłodzenie. Zawodnik ćwiczy sam lub z rodzicem, więc ćwiczenia muszą być proste do wykonania. '
    "Korzystaj z ogólnych zasad bezpiecznego treningu piłkarskiego i autorskich ćwiczeń. "
    'Uwzględnij 1 dzień odpoczynku i co najmniej 1 dzień o niższej intensywności. '
    'Jeśli podano dni treningów klubowych, NIE układaj w te dni treningu - '
    "zwróć dla nich tylko focus 'Trening klubowy', title 'Trening klubowy' i puste steps "
    '(zostaną uzupełnione automatycznie). Uwzględnij obciążenie klubowe: dzień po treningu '
    'klubowym planuj lżej, a dzień przed meczem bez wysokiej intensywności. '
    'Jeśli w promptie podano listę "Zaplanowane przez zawodnika w kalendarzu", te wydarzenia '
    'mają PIERWSZEŃSTWO - w te dni NIE układaj własnego treningu, zwróć tylko focus i tytuł '
    'danego wydarzenia (np. Mecz, Trening klubowy) i puste steps (zostanie nadpisane '
    'automatycznie). Te wydarzenia mają pierwszeństwo także nad dniem odpoczynku. '
    'Nie używaj emoji.';

const String kWeakSpotsSystem =
    "Jesteś indywidualnym trenerem piłkarskim analizującym notatki młodego zawodnika z pola 'Co trzeba poprawić?'. "
    'Zidentyfikuj powtarzające się słabości i zwróć WYŁĄCZNIE poprawny JSON (bez markdown, komentarzy) o schemacie: '
    '{"weak_spots":[{"area":"Technika|Strzał|Taktyka|Motoryka|Mentalność|Inne","insight":"max 1 zdanie konkretnej obserwacji","priority":"low|medium|high"}]}'
    ' Zwróć 2-5 pozycji, najważniejsze najpierw. Nie oceniaj dziecka – wskaż obszar i co z tym zrobić. '
    "Opieraj się na obserwacjach zawodnika i ogólnych zasadach treningu. Pisz po polsku. Nie używaj emoji.";

const Map<String, String> _drillTips = <String, String>{
  'drill-prowadzenie':
      'Głowa do góry między dotknięciami piłki i kontrola tempa – wolniej, ale czysto.',
  'drill-strzal':
      'Stabilna noga podporowa, ciało nad piłką i celuj w róg bramki, nie tylko mocno.',
  'drill-decyzyjnosc':
      'Zanim dostaniesz piłkę, sprawdź ustawienie rywala i wolną przestrzeń.',
  'drill-sila':
      'Technika ważniejsza niż liczba powtórzeń – ruch ma być kontrolowany.',
  'drill-mentalnosc':
      'Skup się na jednym celu na dziś i oddychaj spokojnie – bez pośpiechu.',
};

const Map<String, List<String>> _drillKeywords = <String, List<String>>{
  'drill-strzal': <String>['strza', 'bramk', 'gol', 'finaliz'],
  'drill-prowadzenie': <String>[
    'prowadz',
    'drybl',
    'zwód',
    'zwod',
    'technik',
    'piłk',
    'pilk',
    'slalom',
  ],
  'drill-decyzyjnosc': <String>[
    'decyz',
    '1v1',
    'pojedyn',
    'czyta',
    'taktyk',
    'ustaw',
  ],
  'drill-sila': <String>[
    'sił',
    'sil',
    'szybk',
    'wytrzym',
    'kondyc',
    'motoryk',
    'bieg',
  ],
  'drill-mentalnosc': <String>[
    'mentaln',
    'stres',
    'pewno',
    'nerw',
    'koncentr',
    'motywac',
    'trema',
  ],
};

/// Odpowiedź trenera w trybie offline (bez klucza AI) - w tym samym
/// formacie 3 sekcji, który wymusza polecenie systemowe.
String offlineCoachReply(String message) {
  final m = message.toLowerCase();
  const painWords = <String>[
    'ból',
    'boli',
    'kontuz',
    'uraz',
    'skręc',
    'kolano',
  ];
  for (final w in painWords) {
    if (m.contains(w)) {
      return '1) Krótka motywacja\n'
          'Dobrze, że o tym mówisz – zdrowie jest ważniejsze niż jeden trening.\n\n'
          '2) Co dzisiaj zrobić\n'
          '- Przerwij ćwiczenia, które powodują ból.\n'
          '- Powiedz o tym rodzicowi lub trenerowi klubowemu.\n'
          '- Wróć do treningu dopiero, gdy dorosły uzna, że możesz.\n\n'
          '3) Na co zwrócić uwagę\n'
          'Nie ćwicz „na siłę” i nie diagnozuj się sam – ból oceni dorosły lub lekarz.';
    }
  }

  Map<String, dynamic>? chosen;
  for (final entry in _drillKeywords.entries) {
    for (final k in entry.value) {
      if (m.contains(k)) {
        chosen = kDrills.firstWhere((d) => d['id'] == entry.key);
        break;
      }
    }
    if (chosen != null) break;
  }
  chosen ??= kDrills[DateTime.now().weekday % kDrills.length];

  final motivation = kMotivations[DateTime.now().weekday % kMotivations.length];
  final steps = (chosen['steps'] as List<String>).take(5).toList();
  final tip = _drillTips[chosen['id']] ?? '';

  final b = StringBuffer()
    ..writeln('1) Krótka motywacja')
    ..writeln(motivation)
    ..writeln()
    ..writeln(
      '2) Co dzisiaj zrobić (${chosen['title']}, ${chosen['duration_min']} min)',
    );
  for (final s in steps) {
    b.writeln('- $s');
  }
  b
    ..writeln()
    ..writeln('3) Na co zwrócić uwagę')
    ..writeln(tip)
    ..writeln()
    ..write(
      '(Tryb offline – wpisz własny klucz AI w ustawieniach, '
      'aby trener odpowiadał na dowolne pytania.)',
    );
  return b.toString();
}

/// Rozpisane kroki dla dnia planu (gdy plan nie zawiera kroków,
/// np. w trybie offline lub w starszym zapisanym planie).
List<String> planStepsFor(String focus) {
  switch (focus) {
    case 'Odpoczynek':
      return const <String>[
        'Lekki spacer lub jazda na rowerze: 15-20 min, spokojne tempo.',
        'Rozciąganie: łydki, uda, biodra i plecy - po 30 s na każdą stronę.',
        'Rolowanie mięśni nóg (jeśli masz roller): 5 min.',
        'Pij dużo wody i śpij co najmniej 9 godzin - mięśnie rosną w czasie odpoczynku.',
      ];
    case 'Mecz':
      return const <String>[
        'Rozgrzewka meczowa: 10 min truchtu, skipy A i C, krążenia bioder.',
        'Podania w parach lub o ścianę: 5 min, obie nogi.',
        'Przyspieszenia: 4 x 15 m, wracaj marszem.',
        'Wyznacz jeden cel na mecz, np. 3 udane dryblingi albo 5 odbiorów.',
        'Po meczu: 10 min schłodzenia i zapisz mecz w dzienniku.',
      ];
    case 'Trening klubowy':
      return const <String>[
        'Spakuj torbę: buty, ochraniacze, woda. Bądź 10 min przed czasem.',
        'Wybierz jeden cel indywidualny na trening, np. więcej gry słabszą nogą.',
        'Słuchaj trenera i zadawaj pytania, gdy czegoś nie rozumiesz.',
        'Po treningu: 5 min rozciągania i posiłek w ciągu godziny.',
        'Zapisz trening w dzienniku - co wyszło, a co poprawić.',
      ];
  }
  for (final d in kDrills) {
    if (d['focus'] == focus) return List<String>.from(d['steps'] as List);
  }
  return const <String>[
    'Rozgrzewka: 5-10 min truchtu i rozciągania dynamicznego.',
    'Prowadzenie piłki slalomem między pachołkami: 4 serie po 2 przejścia.',
    'Podania o ścianę obiema nogami: 3 x 20 powtórzeń.',
    'Schłodzenie i rozciąganie: 5 min.',
  ];
}

/// Wskazówka trenera dla danego obszaru.
String planTipFor(String focus) {
  switch (focus) {
    case 'Odpoczynek':
      return 'Odpoczynek to też trening - bez niego nie będzie postępów.';
    case 'Mecz':
      return 'Graj odważnie - błędy są częścią nauki.';
    case 'Trening klubowy':
      return 'Na treningu klubowym daj z siebie 100% w każdym ćwiczeniu.';
  }
  for (final d in kDrills) {
    if (d['focus'] == focus) return _drillTips[d['id']] ?? '';
  }
  return '';
}
