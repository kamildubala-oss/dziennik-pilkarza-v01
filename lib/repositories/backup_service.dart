part of '../api.dart';

/// Wydzielona implementacja BackupService. Publiczny interfejs pozostaje w Api.
class BackupService {
  static Future<String> exportBackup() async {
    final data = await LocalDb.exportAll();
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'app': Api._backupApp,
      'version': 1,
      'exported_at': _nowIso(),
      'counts': <String, int>{
        'trainings': (data['trainings'] as List?)?.length ?? 0,
        'matches': (data['matches'] as List?)?.length ?? 0,
        'events': (data['events'] as List?)?.length ?? 0,
      },
      'data': data,
    });
  }

  static Map<String, int> inspectBackup(String json) {
    final data = Api._parseBackup(json);
    int len(String k) => (data[k] is List) ? (data[k] as List).length : 0;
    return <String, int>{
      'trainings': len('trainings'),
      'matches': len('matches'),
      'events': len('events'),
    };
  }

  static Future<void> importBackup(String json) async {
    await LocalDb.importAll(Api._parseBackup(json));
  }

  static Future<String> exportTrainingsCsv() async {
    final items = _sortedBy(await LocalDb.list('trainings'), 'date');
    return Api._csvDoc(
      <String>[
        'Data',
        'Rodzaj',
        'Obszary',
        'Czas (min)',
        'Intensywność',
        'Ocena (1-5)',
        'Co było dobrze',
        'Co trzeba poprawić',
        'Notatki',
      ],
      <List<dynamic>>[
        for (final t in items)
          <dynamic>[
            first10(_s(t['date'])),
            _s(t['kind']) == 'club_training' ? 'Klubowy' : 'Własny',
            _s(t['focus']),
            _i(t['duration_min']),
            intensityLabel(_s(t['intensity'])),
            _i(t['rating']) > 0 ? _i(t['rating']) : '',
            t['went_well'],
            t['to_improve'],
            t['notes'],
          ],
      ],
    );
  }

  static Future<String> exportMatchesCsv() async {
    final items = _sortedBy(await LocalDb.list('matches'), 'date');
    return Api._csvDoc(
      <String>[
        'Data',
        'Przeciwnik',
        'Wynik',
        'Minuty',
        'Gole',
        'Asysty',
        'Ocena (1-5)',
        'Co było dobrze',
        'Co trzeba poprawić',
        'Notatki',
      ],
      <List<dynamic>>[
        for (final m in items)
          <dynamic>[
            first10(_s(m['date'])),
            m['opponent'],
            m['result'],
            _i(m['minutes_played']),
            _i(m['goals']),
            _i(m['assists']),
            _i(m['rating']) > 0 ? _i(m['rating']) : '',
            m['went_well'],
            m['to_improve'],
            m['notes'],
          ],
      ],
    );
  }
}
