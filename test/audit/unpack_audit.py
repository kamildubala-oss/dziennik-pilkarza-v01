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
print(f"Przygotowano {len(ALLOWED)} pliki źródłowe i 55 testów audytowych.")
