#!/usr/bin/env python3
"""Odtwórz 55 testów audytu jako źródła Dart przed flutter test.

Kod pochodzi z pakietu audit-tests-package.zip przekazanego przez użytkownika.
Testy dokumentujące naprawione błędy A4/A6/W1/W2/W4/W5/W8 mają zmienione
asercje (sprawdzają poprawne działanie). Pozostałe testy zachowują zakres.
"""
from pathlib import Path
from io import BytesIO
import base64
import hashlib
import tarfile

ROOT = Path(__file__).resolve().parents[2]
PARTS = ROOT / "test" / "audit"
OUT = ROOT / "test" / "audit_generated"
EXPECTED = "e714154e24035a4b931b43877ae47476ebf3b67619aadfb82dafe80bf0e2244f"
ALLOWED = {
    "audit_test.dart",
    "verify_gaps_test.dart",
    "smoke_screens_test.dart",
    "plan_focus_test.dart",
}

archive_b64 = "".join(
    (PARTS / f"archive.{i}.txt").read_text(encoding="utf-8").strip()
    for i in range(4)
)
if hashlib.sha256(archive_b64.encode("ascii")).hexdigest() != EXPECTED:
    raise SystemExit("Pliki pakietu audytowego mają błędną sumę kontrolną.")
data = base64.b64decode(archive_b64, validate=True)
OUT.mkdir(exist_ok=True)
with tarfile.open(fileobj=BytesIO(data), mode="r:gz") as archive:
    members = archive.getmembers()
    if {m.name for m in members} != ALLOWED:
        raise SystemExit("Nieoczekiwane pliki w archiwum audytowym.")
    for member in members:
        if not member.isfile() or member.name.startswith("."):
            raise SystemExit("Niedozwolony typ pliku w archiwum audytowym.")
        stream = archive.extractfile(member)
        if stream is None:
            raise SystemExit("Nie można odczytać źródła testu.")
        (OUT / member.name).write_bytes(stream.read())
# Test B3 zakładał, że pierwsze z ośmiu przyszłych wydarzeń klubowych
# można zapisać jako WYKONANE. Sprint 1 słusznie blokuje datę przyszłą.
# Użyj wydarzenia klubowego z bieżącą datą, jeśli żadne nie jest jeszcze
# zaległe. W ten sposób test nadal bada utworzenie wpisu + jego edycję.
test = OUT / "audit_test.dart"
source = test.read_text(encoding="utf-8")
old = "final ev = (await Api.listEvents()).firstWhere((e) => e.type == 'club_training');"
new = """final clubEvents = (await Api.listEvents())
          .where((e) => e.type == 'club_training' && first10(e.date).compareTo(todayIso()) <= 0)
          .toList();
      final ev = clubEvents.isNotEmpty ? clubEvents.first : await Api.createEvent(
        date: todayIso(), type: 'club_training', title: 'Trening klubowy',
        description: 'Trening klubowy', details: <String, dynamic>{
          'duration_min': 90, 'intensity': 'medium',
        },
      );"""
if source.count(old) != 1:
    raise SystemExit("Nie znaleziono jednoznacznie scenariusza B3.")
test.write_text(source.replace(old, new), encoding="utf-8")

# W2/G3 mogą wybrać przyszły dzień planu (np. gdy dziś jest regeneracja).
# Wykonanie zapisujemy z dzisiejszą datą, zachowując ID planu i wszystkie
# asercje powiązania oraz braku duplikatów. Nie omijamy walidacji dat API.
for filename, old, expected_count in [
    ("verify_gaps_test.dart", "date: first10(target.date)", 2),
    ("audit_test.dart", "date: first10(day.date)", 1),
]:
    path = OUT / filename
    source = path.read_text(encoding="utf-8")
    if source.count(old) != expected_count:
        raise SystemExit(f"Nie znaleziono scenariuszy wykonania planu w {filename}.")
    path.write_text(source.replace(old, "date: todayIso()"), encoding="utf-8")

# P3-1 zmienia nazwę radaru; smoke test ma sprawdzać nową etykietę.
smoke = OUT / "smoke_screens_test.dart"
source = smoke.read_text(encoding="utf-8")
old = "MAPA UMIEJĘTNOŚCI"
if source.count(old) != 1:
    raise SystemExit("Nie znaleziono etykiety radaru do aktualizacji.")
source = source.replace(old, "AKTYWNOŚĆ W OBSZARACH")
source = source.replace("find.text('Statystyki')", "find.text('Twój postęp')")
# P1/P2: plan, ćwiczenia i rozmowa mają osobne widoki. Sprawdzamy każdy.
source = source.replace(
    "    expect(find.text('GOTOWE TRENINGI'), findsOneWidget);",
    "    await tester.tap(find.text('Ćwiczenia'));\n"
    "    await tester.pumpAndSettle();\n"
    "    expect(find.text('GOTOWE TRENINGI'), findsOneWidget);",
)
source = source.replace(
    "    expect(find.text('CZAT Z TRENEREM'), findsOneWidget);",
    "    await tester.tap(find.text('Rozmowa'));\n"
    "    await tester.pumpAndSettle();\n"
    "    expect(find.text('CZAT Z TRENEREM'), findsOneWidget);",
)
smoke.write_text(source, encoding="utf-8")

# W oryginalnej paczce znajdowały się nieużywane zmienne/importy
# przygotowawcze (audyt nie wymagał analizy statycznej). Tłumimy wyłącznie
# te dwa lintery w importowanych plikach, a nie w kodzie aplikacji.
for name in ALLOWED:
    path = OUT / name
    text = path.read_text(encoding="utf-8")
    path.write_text(
        "// ignore_for_file: unused_import, unused_local_variable\n" + text,
        encoding="utf-8",
    )

print(f"Przygotowano {len(ALLOWED)} pliki źródłowe i 55 testów audytowych.")

