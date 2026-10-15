# Poprawki bezpieczeństwa danych — wersja robocza

Wprowadzono: rozdzielenie planów i dziennika dla nowych wydarzeń, potwierdzanie usuwania i wybór zakresu, komunikaty błędów w kluczowych formularzach, odczyt kalendarza bez zapisu, synchronizację przy starcie/zmianie profilu, bezpieczniejszy import z walidacją i kopią, ochronę CSV przed formułami, usunięcie imienia/klubu z kontekstu AI, krótszy timeout i komunikat AI, usunięcie zbędnych plików i dodanie .gitignore, synchronizację usuwania treningów.

## Ograniczenia
- Nie wykonano `flutter analyze` ani testów urządzeniowych: SDK Flutter nie jest zainstalowane w środowisku.
- Nie wdrożono pełnego refaktoru api.dart, migracji MainActivity do file_picker/share_plus ani rozbudowanego pakietu testów.
- Import przez SharedPreferences ma mechanizm przywracania po wyjątku, ale nie jest transakcją odporną na nagłe zabicie procesu.
- Zmiana modelu Gemini wymaga sprawdzenia w aktualnym katalogu modeli API.
- Archiwum jest wersją roboczą i wymaga weryfikacji kompilacji przed użyciem produkcyjnym.
