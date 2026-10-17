# Wdrożenie UI/UX P1 i P2

Baza: `2738e5395aacd60dcfc5015bc805dbe6499177d1`.
Limit Dziennika pozostaje równy 5. Zmiany przygotowano na lokalnej gałęzi `ui-ux-p1-p2`.

## Zakres

| Obszar | Zmiana | Najważniejsze pliki |
|---|---|---|
| Plan / wykonanie | W planie brak oceny, wyniku, goli, asyst i refleksji o wykonaniu; opisy pól odpowiadają zamiarowi | `screens/log_session_screen.dart`, `screens/log_match_screen.dart`, `repositories/training_repo.dart` |
| Samoocena | Domyślnie brak zaznaczonych gwiazdek; ocenę można pominąć i wyczyścić | `widgets/common.dart`, `models.dart` |
| Dane bez oceny | Wartość 0 oznacza brak samooceny; nie wchodzi do średniej, CSV ma puste pole; kopia akceptuje 0; trener dostaje informację o braku samooceny | `local_db.dart`, `services/progress_calculator.dart`, `repositories/backup_service.dart`, `api.dart` |
| Formularze | Zapis poza przewijaną treścią, w obszarze reagującym na klawiaturę; ochrona przed utratą zmian, potwierdzenie zmiany typu, zachowanie daty | `widgets/form_exit_guard.dart`, formularze, `screens/add_event_screen.dart` |
| Dostępność | Przyciski Material, większe cele dotyku, etykiety ikon, stan zaznaczenia, większe etykiety pól, reakcja kart na dotyk | `widgets/common.dart`, `theme.dart`, ekrany |
| Dziennik | Akcje zależą od statusu; wykonanie można uzupełnić bezpośrednio; plan regeneracji ma własny stan; historia nadal ma 5 pozycji | `screens/diary_screen.dart` |
| Trener | Osobne widoki Plan / Ćwiczenia / Rozmowa; filtry obszarów; maksymalnie 5 wiadomości w widoku rozmowy | `screens/coach_screen.dart` |
| Błędy | Widoczne błędy generowania, zapisu i odczytu; ponowienie operacji; brak surowego wyjątku w odpowiedzi czatu | `screens/coach_screen.dart`, `screens/progress_screen.dart`, `screens/profile_screen.dart` |
| Źródło wyniku | Rzeczywiste online/offline zapisywane dla planów, analiz i odpowiedzi; starszy wynik ma źródło nieznane | `services/coach_runtime.dart`, `services/coach_service.dart`, `services/plan_service.dart`, `models.dart` |
| Profil | Dwa zrozumiałe tryby; tryb i motyw zapisują się przyciskiem Zapisz; klucz zapisuje się osobno w sekcji zaawansowanej | `screens/profile_screen.dart` |
| Realizacja tygodnia | Cele z kalendarza i planu deduplikowane po powiązaniach; wykonanie wymaga wpisu dziennika, regeneracja jawnego potwierdzenia | `services/week_plan_progress.dart`, `services/progress_calculator.dart`, `api.dart` |
| Wykres aktywności | Osobne treningi, klubowe i mecze, zgodne kolory, wartości i opisy tekstowe; zero nie tworzy słupka aktywności | `screens/progress_screen.dart`, `models.dart` |
| Obszary pracy | Liczba treningów obejmujących obszar; bez wagi samooceny i bez automatycznej Mentalności za mecz; dwa rozłączne okresy 14 dni | `services/skill_radar_service.dart`, `services/progress_calculator.dart`, `screens/progress_screen.dart` |
| Hierarchia Postępu | Realizacja tygodnia, obszar następnego treningu i przejście do ćwiczeń; jedna średnia; lista odznak rozwijana | `screens/progress_screen.dart` |

## Zależności i zgodność danych

1. Wspólne formularze zachowują oddzielne operacje zapisu planu, edycji i wykonania.
2. Starsze dane planów nadal mogą wypełniać formularz z pól strukturalnych lub opisu. Nowe plany nie zapisują ocen wykonania.
3. Brak oceny jest reprezentowany przez 0, nie przez automatyczne 3/5. Istniejące świadomie lub wcześniej zapisane oceny pozostają zachowane; aplikacja nie zgaduje ich pochodzenia.
4. Potwierdzenia regeneracji są osobnym dokumentem `recovery_days`, nie treningami. Nie zwiększają liczby sesji, minut ani serii treningowej.
5. Statystyka obszarów opisuje liczbę treningów, nie pomiar umiejętności. Jeden trening może dotyczyć kilku obszarów.
6. Okresy porównania to dziś i 13 wcześniejszych dni oraz poprzednie 14 dni. Bez nakładania się dat.
7. Ręcznie zmieniony termin kalendarza ma pierwszeństwo; niezwiązana aktywność nie zalicza automatycznie innego celu.

## Sprawdzenia

Wykonano 12 lokalnych sprawdzeń offline rzeczywistych klas Dart: deduplikacja obszarów i powiązań planu, brak automatycznej mentalności za mecz, wykluczanie przyszłej regeneracji i brakującego wpisu, pusty plan, wygasanie serii, modele bez oceny, plan bez oceny, odczyt starszych danych i rozpoznanie regeneracji. Analiza użytego programu sprawdzającego zakończyła się bez problemów.

Dodano testy `ux_forms_test.dart` i `ux_progress_test.dart`. Istniejące scenariusze wykonania, edycji i testy audytowe dostosowano do świadomego rozdziału planu od wykonania i trzech widoków Trenera. Nie usunięto asercji zachowania identyfikatorów i braku duplikatów.

Do wykonania przed scaleniem: pełne `flutter test`, `flutter analyze`, kompilacja Android ARM64 oraz sprawdzenie wizualne aktualnego APK na urządzeniu (oba motywy, klawiatura, większa czcionka i TalkBack).

## Stan publikacji

Za zgodą użytkownika gałąź została wysłana do GitHuba i utworzono PR #11:
https://github.com/kamildubala-oss/dziennik-pilkarza-v01/pull/11

GitHub Actions sprawdza pełne testy, analizę Dart i budowę APK ARM64. Dodano 12 scenariuszy układu głównych ekranów przy szerokości 320 px i skali tekstu 150%, w obu motywach. Pierwsze przebiegi wykryły nieprawidłowe opisy semantyczne pasków postępu, brak podłoża Material oraz przepełnienia wąskich układów; poprawki pozostają w tej samej gałęzi. Zdalny `main` nie został zmieniony.

Pełna ocena na fizycznym telefonie, w tym z TalkBack, pozostaje osobnym sprawdzeniem ręcznym.
