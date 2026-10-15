# Dziennik Młodego Piłkarza — Flutter (Android Studio)

Aplikacja przepisana z React Native (Expo) na **Flutter + Dart**: ten sam wygląd (ciemny „Volt Green” i jasny
motyw, czcionki Barlow Condensed + Manrope, ikony MDI), ten sam UX i wszystkie funkcje.

## Backend jest wbudowany w aplikację — nic nie trzeba uruchamiać

Dawny serwer (FastAPI + MongoDB) został przeniesiony do samej aplikacji (`lib/api.dart`, `lib/local_db.dart`):

* dane (treningi, mecze, kalendarz, profil, plan tygodnia, analiza) zapisują się **lokalnie na telefonie**,
* **brak serwera, brak MongoDB, brak `--dart-define`, brak adresów IP** — instalujesz i działa,
* aplikacja działa także bez internetu (poza zdjęciami w nagłówkach, które ładują się z sieci).

Funkcje „AI trenera” działają od razu w **trybie offline**: czat odpowiada w 3 sekcjach na podstawie autorskich ćwiczeń,
plan tygodnia generuje się z gotowego szablonu dopasowanego do pozycji i celu, a słabe punkty wyliczane są
ze słów kluczowych w notatkach. Chcesz odpowiedzi prawdziwego modelu językowego? Jednorazowo wklej klucz API
w `lib/config.dart` (`llmApiKey`, opcjonalnie `llmBaseUrl` i `llmModel` — dowolny dostawca zgodny z OpenAI).
Uwaga: klucz wpisany w aplikację da się odczytać z pliku APK, więc użyj klucza z limitem wydatków.

Stary serwer zostawiłem w folderze `_stary_backend_nieuzywany/` tylko jako referencję — do działania aplikacji
nie jest potrzebny i można go usunąć. Dane z dawnej bazy MongoDB nie są przenoszone automatycznie.

## Wymagane programy

1. **Flutter SDK (stable)** — https://docs.flutter.dev/get-started/install (dodaj `flutter\bin` do `PATH`).
2. **Android Studio** + wtyczki **Flutter** i **Dart**; w SDK Manager zainstaluj Android SDK, Platform-Tools, Build-Tools.
3. `flutter doctor --android-licenses`, potem `flutter doctor -v` (Android ma być na zielono).

Rozpakuj projekt do krótkiej ścieżki bez spacji i polskich znaków, np. `C:\Projekty\dziennik_pilkarza`.

## Uruchomienie (bez żadnych skryptów)

Projekt zawiera gotowy folder `android/` — wystarczy go otworzyć w Android Studio.

1. Android Studio → **File → Open** → wybierz folder projektu (ten z `pubspec.yaml`).
2. Otwórz `pubspec.yaml` i kliknij **Pub get** w żółtym pasku u góry (albo w terminalu: `flutter pub get`).
   To pobiera pakiety i automatycznie tworzy `android/local.properties` ze ścieżką do Flutter SDK.
3. Poczekaj na synchronizację Gradle (pierwszy raz kilka minut — pobiera Gradle 8.12 i zależności).
4. Wybierz emulator lub podłączony telefon, konfigurację **main.dart** i kliknij **Run ▶**.

Jeśli Android Studio zapyta o ścieżkę do Flutter SDK (File → Settings → Languages & Frameworks → Flutter),
wskaż folder, w którym zainstalowano Flutter.

## APK do instalacji na telefonie

```bat
flutter build apk --release
```

Albo w Android Studio: **Build → Flutter → Build APK**.
Wynik: `build\app\outputs\flutter-apk\app-release.apk` — kopiujesz na telefon i instalujesz. Działa samodzielnie.
(Podpis do Google Play: https://docs.flutter.dev/deployment/android#sign-the-app)

## Struktura

```
android/              gotowy projekt Android (Gradle, manifest, ikony) — nic nie trzeba generować
design/               oryginalne grafiki ikon (źródło)
lib/
  main.dart, theme.dart, config.dart, utils.dart, models.dart, resource.dart
  api.dart            "backend" w aplikacji: treningi, mecze, kalendarz, postęp, profil, plan, czat
  local_db.dart       lokalna baza (zastępuje MongoDB)
  coach_content.dart  ćwiczenia autorskie, motywacje, polecenia dla AI, odpowiedzi offline
  llm.dart            opcjonalny klient modelu AI
  widgets/common.dart wspólne komponenty
  screens/            Dziennik, Kalendarz, Trener, Postęp + modale (profil, trening, mecz, wydarzenie, ćwiczenie)
```

## Poprawki względem wersji React (wygląd bez zmian)

1. **Daty w strefie lokalnej** — oryginał liczył daty w UTC, przez co w Polsce siatka kalendarza i „dziś”
   mogły być przesunięte o dzień. Seria dni, wykres 7 dni i „dziś” używają teraz czasu lokalnego.
2. **Podpisy wykresu „Ostatnie 7 dni”** odpowiadają rzeczywistym dniom (wcześniej na sztywno Pn–Nd).

## Rozwiązywanie problemów

* **`flutter.sdk nie jest ustawione w local.properties`** — uruchom **Pub get** (albo `flutter pub get`); plik zostanie utworzony.
* **Błąd wersji Gradle / Android Gradle Plugin** — projekt używa Gradle 8.12, AGP 8.9.1 i Kotlin 2.1.0 (JDK 17+, dołączone do
  Android Studio). Jeśli Twoja wersja Fluttera narzuca inne, zmień numery w `android/settings.gradle.kts`
  i `android/gradle/wrapper/gradle-wrapper.properties` albo wklej mi komunikat.
* **`flutter: command not found`** — dodaj Flutter SDK do `PATH`, otwórz nowe okno terminala.
* **Błąd Gradle / JDK** — Android Studio: *Settings → Build Tools → Gradle → Gradle JDK* → JDK dołączone do Android Studio (jbr).
* **Błąd ikon w `flutter build apk`** (icon tree shaking) — dodaj `--no-tree-shake-icons`.
* **`pub get` nie dobiera wersji** — `flutter pub upgrade` albo zmień wersję pakietu w `pubspec.yaml`.
* **Dziwne błędy po zmianach** — `flutter clean` i `flutter pub get`.

## Zasoby offline i prywatność obrazów

W APK jest tylko `assets/offline_coach/exercise_library_v2.json`. Pięć pozostałych plików opisujących przyszłe funkcje przeniesiono do `docs/offline_coach/`. Obraz na ekranie trenera pochodzi z lokalnego `assets/images/goal_individual.webp`; ekran nie pobiera obrazu z Unsplash. Korzystanie z trenera AI po podaniu klucza nadal wymaga połączenia z usługą Gemini.
