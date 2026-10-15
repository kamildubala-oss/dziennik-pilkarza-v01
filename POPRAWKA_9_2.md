# Poprawka 9.2 — formularze wydarzeń

- Przywrócono pełny formularz treningu (obszary, intensywność, ocena, co poszło dobrze, co poprawić, notatka) przy dodawaniu wydarzenia typu Trening / Trening klubowy.
- Przywrócono pełny formularz meczu (rywal, wynik, minuty, gole, asysty, ocena i opis) przy dodawaniu wydarzenia typu Mecz.
- W trybie planowania formularze tworzą tylko wydarzenie kalendarza, bez zapisu w kolekcjach `trainings` / `matches` i bez zwiększania statystyk.
- Dane wpisane w formularzu planowania są zapisywane w opisie wydarzenia.

## Ograniczenia
- Zaplanowane szczegóły są obecnie przechowywane jako tekst w opisie wydarzenia, nie jako osobne pola do edycji; edycja istniejącego planu nadal używa formularza ogólnego.
- Nie uruchomiono kompilacji Flutter ani testów urządzeniowych (brak SDK Flutter w środowisku).
