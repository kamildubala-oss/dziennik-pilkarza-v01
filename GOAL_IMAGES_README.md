# Tła karty „Dzisiejszy cel” — Dziennik

Cztery lokalne obrazy WebP, wygenerowane na podstawie zaakceptowanego kolażu (nie są pobierane z internetu):
- `goal_match.webp` — mecz;
- `goal_team.webp` — trening klubowy;
- `goal_individual.webp` — trening indywidualny;
- `goal_rest.webp` — brak aktywności, regeneracja, dzień wolny lub wyłącznie notatki.

W `lib/screens/diary_screen.dart` metoda `_goalBackground` wybiera obraz dla aktualnie wybranego dnia w pasku tygodnia. Przy wielu wydarzeniach priorytet to mecz, klub, trening indywidualny, odpoczynek.

Czytelność: gradient od `#330B1015` u góry do `#FA0B1015` na dole, biały tekst oraz kontrastowy, nieprzezroczysty przycisk „ZAPYTAJ TRENERA”. Grafiki są lokalne, więc działają offline.

Uwaga: brak możliwości uruchomienia Flutter SDK w tym środowisku; należy wykonać `flutter pub get`, `flutter analyze` i test na telefonie.
