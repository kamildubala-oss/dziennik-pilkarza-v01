# Trener offline 9.4

Pakiet v2.2: 60 autorskich ćwiczeń, pliki zasad obciążeń, trendów, planowania i lokalnej bazy wiedzy.

Profil → Trener AI → Tryb trenera:
- Automatyczny: Gemini, jeśli skonfigurowano klucz; przy błędzie połączenia czat przechodzi na offline.
- Tylko offline: nie są wykonywane żadne zapytania do Gemini (również jeśli klucz jest zapisany).
- Gemini: korzysta z klucza, a przy awarii czat przechodzi na offline.

Bez klucza wszystkie funkcje korzystają z logiki lokalnej. Plan tygodnia wykorzystuje bibliotekę ćwiczeń i uwzględnia klubowe oraz ręcznie zaplanowane wydarzenia. Analiza słabych punktów wykorzystuje istniejące lokalne reguły słów kluczowych, gdy AI jest niedostępne.

Ograniczenia: baza JSON reguł obciążeń, trendów i wiedzy jest dołączona jako zasoby, ale pełna interpretacja tych reguł nie została jeszcze zaimplementowana w kodzie. Trener offline nie jest generatywnym modelem językowym. Brak kompilacji i testów na urządzeniu w tym środowisku.

Uwaga: przed publikacją sprawdź plik lib/config.dart i usuń wszelkie wbudowane klucze. Nie publikuj kluczy w repozytorium.
