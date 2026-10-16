import 'dart:convert';

import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> training(String date, {String id = 't1', int minutes = 45}) =>
    <String, dynamic>{
      'id': id,
      'date': date,
      'duration_min': minutes,
      'focus': 'Strzał',
      'focuses': <String>['Strzał'],
      'intensity': 'medium',
      'rating': 3,
      'went_well': '',
      'to_improve': '',
      'notes': '',
    };

Future<void> addTraining({String? date, int minutes = 45}) =>
    Api.createTraining(
      date: date ?? todayIso(),
      durationMin: minutes,
      focuses: <String>['Strzał'],
      intensity: 'medium',
      rating: 3,
      wentWell: '',
      toImprove: '',
      notes: '',
    ).then((_) {});

String backupWith(Map<String, dynamic> data) => jsonEncode(<String, dynamic>{
      'app': 'dziennik_pilkarza',
      'version': 1,
      'data': data,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  setUp(() async => (await SharedPreferences.getInstance()).clear());

  group('P1-1 / W4 - bezpieczny zapis kolekcji', () {
    test('uszkodzony JSON wraca do ostatniej dobrej wersji zamiast pustej listy',
        () async {
      await addTraining();
      final sp = await SharedPreferences.getInstance();
      await sp.setString('mp.db.trainings', '{uszkodzony JSON');
      final entries = await Api.listTrainings();
      expect(entries, hasLength(1));
      expect(sp.getString('mp.db.trainings'), isNot('{uszkodzony JSON'));
      await addTraining(minutes: 60);
      expect(await Api.listTrainings(), hasLength(2));
    });

    test('uszkodzona główna wartość NIE nadpisuje dobrej kopii', () async {
      await addTraining();
      final sp = await SharedPreferences.getInstance();
      final previous = sp.getString('mp.recovery.trainings.1');
      expect(previous, isNotNull);
      await sp.setString('mp.db.trainings', 'to nie JSON');
      await addTraining(minutes: 30);
      expect(await Api.listTrainings(), hasLength(2));
      expect(jsonDecode(sp.getString('mp.recovery.trainings.1')!) as List, hasLength(2));
      expect(previous, isNot('to nie JSON'));
    });

    test('rotacja: drugi slot ratuje kolekcję, gdy pierwszy jest uszkodzony',
        () async {
      await addTraining();
      await addTraining(minutes: 30);
      final sp = await SharedPreferences.getInstance();
      await sp.setString('mp.db.trainings', '{fatal');
      await sp.setString('mp.recovery.trainings.1', '{fatal');
      expect(await Api.listTrainings(), hasLength(1));
    });

    test('brak obu kopii = widoczny błąd zamiast usunięcia wpisów', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('mp.db.trainings', '{fatal');
      await expectLater(Api.listTrainings(), throwsA(isA<FormatException>()));
      await expectLater(addTraining(), throwsA(isA<FormatException>()));
      expect(sp.getString('mp.db.trainings'), '{fatal');
    });

    test('uszkodzony JSON nie znika cicho podczas eksportu', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('mp.db.trainings', '{fatal');
      await expectLater(Api.exportBackup(), throwsA(isA<FormatException>()));
    });

    test('kopie awaryjne nie wyciekają do eksportu użytkownika', () async {
      await addTraining();
      final export = await Api.exportBackup();
      expect(export.contains('mp.recovery.'), false);
      expect(export.contains('trainings'), true);
    });

    test('po poprawnym imporcie kopia awaryjna należy do nowego dziennika',
        () async {
      await addTraining();
      final doc = backupWith(<String, dynamic>{
        'trainings': <Map<String, dynamic>>[
          training('2025-02-01', id: 'imported')
        ],
      });
      await Api.importBackup(doc);
      final sp = await SharedPreferences.getInstance();
      await sp.setString('mp.db.trainings', '{fatal');
      final entries = await Api.listTrainings();
      expect(entries, hasLength(1));
      expect(entries.single.id, 'imported');
    });
  });

  group('P1-2 / A6 / W5 - walidacja dat i importu', () {
    test('przyszły wykonany trening jest odrzucany, plan jest dozwolony',
        () async {
      final future = DateTime.now().add(const Duration(days: 5));
      final date = dateIso(future);
      await expectLater(addTraining(date: date), throwsA(isA<ApiException>()));
      await Api.createTraining(
        date: date, durationMin: 45,
        focuses: <String>['Strzał'], intensity: 'medium', rating: 3,
        wentWell: '', toImprove: '', notes: '', isPlanned: true,
      );
      expect(await Api.listTrainings(), isEmpty);
      expect(await Api.listEvents(), hasLength(1));
    });

    test('przyszły wykonany mecz też jest odrzucany', () async {
      final date = dateIso(DateTime.now().add(const Duration(days: 2)));
      await expectLater(
        Api.createMatch(
          date: date, opponent: 'Rywal', result: '1:0', minutesPlayed: 60,
          goals: 1, assists: 0, rating: 3, wentWell: '',
          toImprove: '', notes: '',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('błędna data kalendarzowa (30 lutego) jest odrzucana', () async {
      await expectLater(
        addTraining(date: '2026-02-30'), throwsA(isA<ApiException>()),
      );
    });

    test('aktualizacja treningu nie przyjmuje ujemnego ani nadmiernego czasu',
        () async {
      await addTraining();
      final id = (await Api.listTrainings()).single.id;
      for (final duration in <int>[-5, 601]) {
        expect(
          () => Api.updateTraining(
            id, durationMin: duration, rating: 3,
            wentWell: '', toImprove: '', notes: '',
          ),
          throwsA(isA<ApiException>()),
        );
      }
      expect((await Api.listTrainings()).single.durationMin, 45);
    });

    test('aktualizacja meczu waliduje minuty i gole', () async {
      final match = await Api.createMatch(
        date: todayIso(), opponent: 'Rywal', result: '0:0', minutesPlayed: 60,
        goals: 0, assists: 0, rating: 3, wentWell: '', toImprove: '', notes: '',
      );
      expect(
        () => Api.updateMatch(match.id,
          date: todayIso(), opponent: 'Rywal', result: '', minutesPlayed: 181,
          goals: 0, assists: 0, rating: 3, wentWell: '', toImprove: '', notes: '',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => Api.updateMatch(match.id,
          date: todayIso(), opponent: 'Rywal', result: '', minutesPlayed: 60,
          goals: 99, assists: 0, rating: 3, wentWell: '', toImprove: '', notes: '',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('W5: błędny rekord importu (data/czas/ocena) jest odrzucany', () async {
      final invalid = backupWith(<String, dynamic>{
        'trainings': <Map<String, dynamic>>[
          training('nie-data', minutes: -5)..['rating'] = 99,
        ],
      });
      expect(() => Api.inspectBackup(invalid), throwsA(isA<ApiException>()));
      await expectLater(Api.importBackup(invalid), throwsA(isA<ApiException>()));
      expect(await Api.listTrainings(), isEmpty);
    });

    test('import z datą poprawną lecz liczbą spoza zakresu jest odrzucany',
        () async {
      final invalid = backupWith(<String, dynamic>{
        'trainings': <Map<String, dynamic>>[
          training('2025-01-01', minutes: -5)
        ],
      });
      await expectLater(Api.importBackup(invalid), throwsA(isA<ApiException>()));
    });

    test('wadliwy import nie nadpisuje istniejących danych', () async {
      await addTraining();
      final id = (await Api.listTrainings()).single.id;
      final invalid = backupWith(<String, dynamic>{
        'trainings': <Map<String, dynamic>>[
          training('2025-01-01')..['rating'] = 100,
        ],
      });
      await expectLater(Api.importBackup(invalid), throwsA(isA<ApiException>()));
      expect((await Api.listTrainings()).single.id, id);
    });

    test('poprawny eksport i import pozostają kompatybilne', () async {
      await addTraining();
      final serialized = await Api.exportBackup();
      final sp = await SharedPreferences.getInstance();
      await sp.clear();
      await Api.importBackup(serialized);
      expect(await Api.listTrainings(), hasLength(1));
    });
  });
}
