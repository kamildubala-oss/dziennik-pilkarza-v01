# Testy regresyjne audytu (55 scenariuszy)

Oryginalny pakiet **audit-tests-package.zip** otrzymany od użytkownika
zawierał cztery pliki testowe i 55 scenariuszy (40 funkcjonalnych,
10 weryfikacyjnych, 4 smoke, 1 plan_focus).

Aby uniknąć duplikowania długich źródeł w kodzie aplikacji, testy znajdują
się w archiwum `archive.0.txt`–`archive.3.txt`. Można je odtworzyć:

```bash
python3 test/audit/unpack_audit.py
flutter test
```

GitHub Actions wykonuje te polecenia podczas każdej kompilacji.
Skrypt weryfikuje SHA-256 archiwum i listę dozwolonych plików.

Testy **A4, A6, W1, W2, W4, W5, W8** zostały przepisane z potwierdzania
dawnego błędu na wymaganie poprawnego zachowania po Sprintach 1–2.
Testy **W3, W7 i W10** nadal opisują znane ograniczenia obecnej wersji;
ich korekta należy do dalszego rozwoju aplikacji.

Po odtworzeniu kod testów jest dostępny w `test/audit_generated/`.
