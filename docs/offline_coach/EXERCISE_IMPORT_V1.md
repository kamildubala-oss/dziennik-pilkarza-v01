# Import ćwiczeń — paczka v1

Źródło: `baza_dziennika_pilkarza_v1.zip` (25.10.2026).

- Biblioteka: 60 → 72 ćwiczenia.
- 12 nowych zadań, 18 odpowiedników scalonych pod dotychczasowymi ID.
- Wszystkie 30 pozycji jest dostępnych w gotowych treningach oraz bibliotece trenera offline.
- Dotychczasowe zapisane plany i wpisy zawodnika nie są przepisywane.
- Porównano cel, organizację i role uczestników, nie tylko podobieństwo tytułu. Różne zadania i warianty organizacji pozostają osobno.
- Zachowano instrukcje, miarę obserwacji, przerwy, filtr wieku, ograniczenia, status przeglądu i odnośniki źródłowe z paczki.
- Źródłowe `low_to_moderate` ma techniczny odpowiednik `medium`; `none` ma odpowiednik `low` i jawny opis braku wysiłku fizycznego. Oryginalna wartość pozostaje w `source_intensity`.
- Podany wiek minimalny jest autorskim filtrem treści, nie normą rozwojową. Paczka nie określa wieku maksymalnego (`null`). Status `do_weryfikacji_trenerskiej` pozostaje zachowany.
- Czasy bloków 5/8 minut pochodzą z paczki; formularz i planer nie zastępują ich domyślnymi 45/10 minutami.
- Dane o pochodzeniu źródeł są w dokumentacji i metadanych, a nie w nazwach kart sugerujących autoryzację federacji.

Pozostałych modułów paczki (SQLite, model obciążeń, wiedza, reguły planera i odpowiedzi czatu) nie importowano — zakres tego wdrożenia obejmuje ćwiczenia.

## Mapowanie

| ID paczki | ID w aplikacji | Operacja | Tytuł zachowanej wersji |
| --- | --- | --- | --- |
| EX001 | tech_first_touch | Scalenie | Przyjęcie do dwóch bramek |
| EX002 | v21_scan_number | Scalenie | Skan przed odbiorem |
| EX003 | tech_passing_gates | Scalenie | Podanie przez okno |
| EX004 | tac_support_angle | Scalenie | Podaj i zmień kąt |
| EX005 | v23_ex005 | Nowe | Wyjście z przyjęciem |
| EX006 | v23_ex006 | Nowe | Zmiana kierunku przy pachołku |
| EX007 | tech_dribble_accel | Scalenie | Zwód i wyjście |
| EX008 | tech_1v1_gate | Scalenie | Pojedynek do dwóch wyjść |
| EX009 | tac_defend_channel | Scalenie | Obrońca kieruje na bok |
| EX010 | v23_ex010 | Nowe | Cień napastnika |
| EX011 | tech_finish_zones | Scalenie | Strzał po bocznym przyjęciu |
| EX012 | tac_finish_after_combination | Scalenie | Wykończenie po odegraniu |
| EX013 | tech_weak_foot | Scalenie | Słabsza noga do celu |
| EX014 | v21_wall_gate_switch | Scalenie | Zmiana strony przez ścianę |
| EX015 | v23_ex015 | Nowe | Podanie po prowadzeniu |
| EX016 | v23_ex016 | Nowe | Ruch od i do piłki |
| EX017 | v23_ex017 | Nowe | Odbiór i pierwsze podanie |
| EX018 | tac_transition_3v2 | Scalenie | Reakcja po utracie |
| EX019 | v23_ex019 | Nowe | Wybór wolnej bramki |
| EX020 | v23_ex020 | Nowe | Komunikat przed podaniem |
| EX021 | v23_ex021 | Nowe | Równowaga z piłką |
| EX022 | phy_coordination_ladder | Scalenie | Koordynacyjna ścieżka |
| EX023 | phy_dynamic_warmup | Scalenie | Przygotowanie ruchowe |
| EX024 | v23_ex024 | Nowe | Dokładność bez pośpiechu |
| EX025 | men_pre_session_goal | Scalenie | Jeden cel na trening |
| EX026 | men_reset_after_error | Scalenie | Powrót po błędzie |
| EX027 | men_confidence_evidence | Scalenie | Trzy dowody przygotowania |
| EX028 | men_post_session_reflection | Scalenie | Pomeczowa refleksja |
| EX029 | v23_ex029 | Nowe | Zrozumieć rolę wahadłowego |
| EX030 | v23_ex030 | Nowe | Współpraca między liniami |

## Ponowny import

`python3 scripts/import_exercise_library.py /ścieżka/baza_dziennika_pilkarza_v1.zip`

Importer sprawdza hash danych wejściowych zatwierdzonych w tym mapowaniu. Zmieniona paczka wymaga ponownego przeglądu odpowiedników. Ponowny import tej samej wersji jest idempotentny. Pełne mapowanie i hash ZIP: `exercise_import_v1.json`; katalog źródeł: `import_sources_v1.json`.
