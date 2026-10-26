#!/usr/bin/env python3
"""Import ćwiczeń z paczki v1; jawne mapowanie równoważnych zadań zachowuje ID."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'baza_dziennika_pilkarza_v1'
EXPECTED_EXERCISE_SHA256 = '11c07952182ec1fc07cdef01d508f215d7b735ec601d8e1066567183f56f02b2'
# Podobna kategoria nie wystarcza: różne zadania/różne role zostają osobno.
DUPLICATES = {
    'EX001': 'tech_first_touch',
    'EX002': 'v21_scan_number',
    'EX003': 'tech_passing_gates',
    'EX004': 'tac_support_angle',
    'EX007': 'tech_dribble_accel',
    'EX008': 'tech_1v1_gate',
    'EX009': 'tac_defend_channel',
    'EX011': 'tech_finish_zones',
    'EX012': 'tac_finish_after_combination',
    'EX013': 'tech_weak_foot',
    'EX014': 'v21_wall_gate_switch',
    'EX018': 'tac_transition_3v2',
    'EX022': 'phy_coordination_ladder',
    'EX023': 'phy_dynamic_warmup',
    'EX025': 'men_pre_session_goal',
    'EX026': 'men_reset_after_error',
    'EX027': 'men_confidence_evidence',
    'EX028': 'men_post_session_reflection',
}
AREAS = {
    'przyjecie': ('technika', 'przyjęcie', 'Prowadzenie'),
    'podanie': ('technika', 'podania', 'Prowadzenie'),
    'prowadzenie': ('technika', 'prowadzenie', 'Prowadzenie'),
    'drybling': ('technika', 'drybling', 'Prowadzenie'),
    'strzal': ('technika', 'strzał', 'Strzał'),
    'obserwacja': ('taktyka', 'obserwacja', 'Decyzyjność'),
    'ruch_bez_pilki': ('taktyka', 'ruch bez piłki', 'Decyzyjność'),
    'obrona_1v1': ('taktyka', 'obrona 1 na 1', 'Decyzyjność'),
    'komunikacja': ('taktyka', 'komunikacja', 'Decyzyjność'),
    'taktyka': ('taktyka', 'rozumienie gry', 'Decyzyjność'),
    'koordynacja': ('motoryka', 'koordynacja', 'Siła'),
    'mental': ('mentalność', 'refleksja', 'Mentalność'),
}

def merge(library, incoming):
    result = copy.deepcopy(library)
    by_id = {e['id']: e for e in result['exercises']}
    if len(by_id) != len(result['exercises']):
        raise ValueError('Powtórzone ID w dotychczasowej bibliotece')
    seen = set()
    mapping = []
    for item in incoming:
        source_id = item['id']
        if source_id in seen:
            raise ValueError(f'Powtórzone ID wejściowe: {source_id}')
        seen.add(source_id)
        canonical = DUPLICATES.get(source_id, f'v23_{source_id.lower()}')
        previous = by_id.get(canonical)
        if source_id in DUPLICATES and previous is None:
            raise ValueError(f'Brak docelowego ćwiczenia: {canonical}')
        origin = f'{PACKAGE}/{source_id}'
        if previous and previous.get('import_origin') == origin:
            mapping.append({'incoming_id': source_id, 'canonical_id': canonical,
                            'action': 'merged' if source_id in DUPLICATES else 'added'})
            continue
        if previous and source_id not in DUPLICATES:
            raise ValueError(f'Kolizja nowego ID: {canonical}')
        persons = item['persons_total']
        if persons not in (1, 2):
            raise ValueError(f'Nieobsługiwana liczba uczestników: {source_id}')
        area, subarea, focus = AREAS[item['skills'][0]]
        entry = copy.deepcopy(previous) if previous else {}
        old_title = entry.get('title')
        old_age_band = entry.get('age_band')
        old_provenance = entry.get('provenance')
        entry.update(copy.deepcopy(item))
        entry.update({
            'id': canonical,
            'import_origin': origin,
            'import_package': PACKAGE,
            'source_exercise_id': source_id,
            'area': area, 'subarea': subarea, 'journal_focus': focus,
            'age_band': {'min': item['min_age'], 'max': None},
            'duration_min': item['session_block_minutes'],
            'source_intensity': item['intensity'],
            'intensity': 'medium' if item['intensity'] == 'low_to_moderate' else 'low',
            'solo': persons == 1, 'participation_mode': 'solo' if persons == 1 else 'coach',
            'participants_min': persons, 'participants_max': persons,
            'requires_team': False,
            'required_human_roles': ['zawodnik'] + (['trener lub partner'] if persons == 2 else []),
            'environment_options': ['samodzielnie'] if persons == 1 else ['zawodnik i trener lub partner'],
            'equipment': [part.strip().lower() for part in item['equipment'].split(',')],
            'goal': entry.get('goal') or f"Przećwicz zadanie: {item['title']}.",
            'setup': item['space'],
            'steps': [item['instructions'], item['work_rest'], f"Obserwuj: {item['success_metric']}"],
            'regression': entry.get('regression') or 'Wykonaj zadanie spokojnie, z pomocą trenera.',
            'progression': entry.get('progression') or 'Omów zmianę trudności z trenerem; nie dodawaj uczestników.',
            'coaching_cues': list(dict.fromkeys([item['work_rest'], item['age_policy'], item['limitations']])),
            'trackable_metrics': list(dict.fromkeys(entry.get('trackable_metrics', []) + [item['success_metric']])),
            'tags': list(dict.fromkeys(entry.get('tags', []) + item['skills'])),
            'provenance': {'type': item['evidence_type'], 'source_refs': item['source_refs'],
                           'source_catalog': 'docs/offline_coach/import_sources_v1.json',
                           'package': PACKAGE},
        })
        if old_title and old_title != item['title']:
            entry['previous_title'] = old_title
        if old_age_band:
            entry['previous_age_band'] = old_age_band
        if old_provenance:
            entry['previous_provenance'] = old_provenance
        by_id[canonical] = entry
        mapping.append({'incoming_id': source_id, 'canonical_id': canonical,
                        'action': 'merged' if previous else 'added'})
    result['exercises'] = list(by_id.values())
    result['schema_version'] = '2.3.0'
    result['count'] = len(result['exercises'])
    result['title'] = f"Biblioteka {result['count']} ćwiczeń — maksymalnie zawodnik i trener"
    result['import_packages'] = list(dict.fromkeys(result.get('import_packages', []) + [PACKAGE]))
    return result, mapping

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('package', type=Path)
    parser.add_argument('--library', type=Path, default=ROOT/'assets/offline_coach/exercise_library_v2.json')
    parser.add_argument('--mapping', type=Path, default=ROOT/'docs/offline_coach/exercise_import_v1.json')
    args = parser.parse_args()
    with zipfile.ZipFile(args.package) as z:
        raw = z.read('baza_dziennika_pilkarza/exercise_library.json')
        if hashlib.sha256(raw).hexdigest() != EXPECTED_EXERCISE_SHA256:
            raise ValueError('Zmieniona paczka ćwiczeń wymaga ponownego przeglądu mapowania duplikatów')
        incoming = json.loads(raw)
        sources = json.loads(z.read('baza_dziennika_pilkarza/sources.json'))
    before = json.loads(args.library.read_text())
    result, mapping = merge(before, incoming)
    args.library.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    args.mapping.parent.mkdir(parents=True, exist_ok=True)
    args.mapping.write_text(json.dumps({'package': PACKAGE,
        'package_sha256': hashlib.sha256(args.package.read_bytes()).hexdigest(),
        'incoming_count': len(incoming), 'canonical_count': len(result['exercises']),
        'entries': mapping}, ensure_ascii=False, indent=2)+'\n')
    args.mapping.with_name('import_sources_v1.json').write_text(json.dumps(sources, ensure_ascii=False, indent=2)+'\n')
    print(f"Baza: {len(before['exercises'])} -> {result['count']}; nowe: {sum(m['action']=='added' for m in mapping)}; scalone: {sum(m['action']=='merged' for m in mapping)}")

if __name__ == '__main__':
    main()
