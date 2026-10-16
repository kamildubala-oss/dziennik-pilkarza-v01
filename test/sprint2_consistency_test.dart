import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<TrainingTestResult> finishTraining(
  String plannedId, {
  int duration = 60,
  String focus = 'Siła',
  String intensity = 'high',
}) async {
  final t = await Api.createTraining(
    date: todayIso(),
    durationMin: duration,
    focuses: <String>[focus],
    intensity: intensity,
    rating: 4,
    wentWell: 'Podania',
    toImprove: 'Przyjęcie',
    notes: 'Test',
    plannedEventId: plannedId,
  );
  return TrainingTestResult(t.id);
}

class TrainingTestResult {
  const TrainingTestResult(this.id);
  final String id;
}

Future<String> plannedTraining({String type = 'training'}) async {
  final event = await Api.createEvent(
    date: todayIso(), time: '17:30', type: type,
    title: 'Trening: Strzał', description: 'Plan 30 minut',
    details: <String, dynamic>{
      'duration_min': 30, 'focus': 'Strzał',
      'focuses': <String>['Strzał'], 'intensity': 'medium',
    },
  );
  return event.id;
}

Future<String> plannedMatch() async {
  final event = await Api.createEvent(
    date: todayIso(), time: '14:00', type: 'match',
    title: 'Mecz z Rywalem', description: 'Plan 45 minut',
    details: <String, dynamic>{
      'minutes_played': 45, 'duration_min': 45, 'opponent': 'Rywal',
    },
  );
  return event.id;
}

Future<String> finishMatch(String plannedId, {int minutes = 80}) async {
  final m = await Api.createMatch(
    date: todayIso(), opponent: 'Legia', result: '2:1',
    minutesPlayed: minutes, goals: 1, assists: 1, rating: 5,
    wentWell: 'Strzały', toImprove: 'Pressing', notes: 'Zagrane',
    plannedEventId: plannedId,
  );
  return m.id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  setUp(() async => (await SharedPreferences.getInstance()).clear());

  group('P1-3: idempotentne wykonanie planu', () {
    test('A4: dwa zapisy tego samego planu zwracają ID jednego treningu', () async {
      final eventId = await plannedTraining();
      final first = await finishTraining(eventId);
      final second = await finishTraining(eventId);
      expect(second.id, first.id);
      expect(await Api.listTrainings(), hasLength(1));
      expect((await Api.listEvents()), hasLength(1));
      expect((await Api.progress()).totalMinutes, 60);
    });

    test('W2: dwa równoległe zapisy nie tworzą duplikatu', () async {
      final eventId = await plannedTraining();
      final results = await Future.wait(<Future<TrainingTestResult>>[
        finishTraining(eventId), finishTraining(eventId),
      ]);
      expect(results[0].id, results[1].id);
      expect((await Api.listTrainings()).length, 1);
      expect((await Api.listEvents()).single.done, true);
    });

    test('ponowne wykonanie meczu zachowuje jeden wpis i jedną statystykę', () async {
      final eventId = await plannedMatch();
      final first = await finishMatch(eventId);
      final second = await finishMatch(eventId);
      expect(first, second);
      expect(await Api.listMatches(), hasLength(1));
      expect((await Api.progress()).totalMinutes, 80);
    });

    test('nieistniejące ID planu nie tworzy luźnego wpisu treningowego', () async {
      await expectLater(
        finishTraining('brak-w-kalendarzu'),
        throwsA(isA<ApiException>()),
      );
      expect(await Api.listTrainings(), isEmpty);
    });

    test('nie można zakończyć meczu jako treningu', () async {
      final id = await plannedMatch();
      await expectLater(finishTraining(id), throwsA(isA<ApiException>()));
      expect(await Api.listTrainings(), isEmpty);
    });

    test('B3: ponowna ocena treningu klubowego EDYTUJE istniejący wpis', () async {
      final id = await plannedTraining(type: 'club_training');
      final event = (await Api.listEvents()).singleWhere((e) => e.id == id);
      await Api.rateClubTraining(
        event, focuses: <String>['Strzał'], rating: 3,
        wentWell: 'Pierwszy zapis', toImprove: '', notes: '',
      );
      final done = (await Api.listEvents()).single;
      await Api.rateClubTraining(
        done, focuses: <String>['Siła'], rating: 5,
        wentWell: 'Lepsza gra', toImprove: '', notes: '',
      );
      expect(await Api.listTrainings(), hasLength(1));
      expect((await Api.listTrainings()).single.rating, 5);
      expect((await Api.listEvents()).single.focus, 'Siła');
    });
  });

  group('P1-4: prawdziwe wykonanie jest źródłem danych kalendarza', () {
    test('W1: plan 30 min/medium/Strzał -> wykonanie 60 min/high/Siła', () async {
      final id = await plannedTraining();
      final result = await finishTraining(id);
      final ev = (await Api.listEvents()).single;
      expect(ev.id, id, reason: 'zachowaj ID i godzinę planu');
      expect(ev.sourceId, result.id);
      expect(ev.time, '17:30');
      expect(ev.done, true);
      expect(ev.durationMin, 60);
      expect(ev.intensity, 'high');
      expect(ev.focus, 'Siła');
      expect(ev.details['focuses'], contains('Siła'));
      expect(ev.description, contains('60 min'));
    });

    test('W8: edycja treningu aktualizuje pola i opis wydarzenia', () async {
      final id = await plannedTraining();
      final t = await finishTraining(id);
      await Api.updateTraining(
        t.id, date: todayIso(), durationMin: 90,
        focuses: <String>['Mentalność'], intensity: 'low', rating: 5,
        wentWell: '', toImprove: '', notes: 'Nowa ocena',
      );
      final ev = (await Api.listEvents()).single;
      expect(ev.durationMin, 90);
      expect(ev.intensity, 'low');
      expect(ev.focus, 'Mentalność');
      expect(ev.description, contains('90 min'));
      expect(ev.details['rating'], 5);
    });

    test('nowy zapis treningu bez planu od razu ma pola strukturalne', () async {
      await Api.createTraining(
        date: todayIso(), durationMin: 40,
        focuses: <String>['Strzał'], intensity: 'high', rating: 3,
        wentWell: '', toImprove: '', notes: '',
      );
      final ev = (await Api.listEvents()).single;
      expect(ev.durationMin, 40);
      expect(ev.focus, 'Strzał');
      expect(ev.intensity, 'high');
    });

    test('mecz: wykonanie i edycja aktualizują minuty, wynik, gole i asysty', () async {
      final id = await plannedMatch();
      final mId = await finishMatch(id);
      var ev = (await Api.listEvents()).single;
      expect(ev.durationMin, 80);
      expect(ev.details['minutes_played'], 80);
      expect(ev.details['goals'], 1);
      await Api.updateMatch(
        mId, date: todayIso(), opponent: 'Zagłębie', result: '3:1',
        minutesPlayed: 90, goals: 2, assists: 0, rating: 4,
        wentWell: 'Podania', toImprove: '', notes: '',
      );
      ev = (await Api.listEvents()).single;
      expect(ev.durationMin, 90);
      expect(ev.title, 'Mecz z Zagłębie');
      expect(ev.details['minutes_played'], 90);
      expect(ev.details['goals'], 2);
      expect(ev.details['assists'], 0);
    });
  });
}
