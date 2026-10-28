import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/llm_settings.dart';
import 'package:dziennik_pilkarza/screens/add_event_screen.dart';
import 'package:dziennik_pilkarza/screens/activity_editor.dart';
import 'package:dziennik_pilkarza/screens/recovery_screen.dart';
import 'package:dziennik_pilkarza/screens/diary_screen.dart';
import 'package:dziennik_pilkarza/services/chat_window.dart';
import 'package:dziennik_pilkarza/widgets/period_selector.dart';
import 'package:dziennik_pilkarza/widgets/exercise_button.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.list('trainings');
  });
  setUp(() async {
    for (final key in ['trainings', 'matches', 'events', 'plans', 'chat_messages']) {
      await LocalDb.saveList(key, []);
    }
    await LlmSettings.setMode('offline');
  });
  Widget shell(Widget child) => MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
    home: Scaffold(body: child));
  test('chat view keeps four replies with their questions and a pending question', () {
    final roles = [for (var i = 0; i < 7; i++) ...['user','assistant'], 'user'];
    final visible = roles.skip(visibleChatStart(roles)).toList();
    expect(visible.where((e) => e == 'assistant').length, 4);
    expect(visible.first, 'user'); expect(visible.last, 'user');
    expect(roles.length, 15);
    expect(visibleChatStart(['user']), 0);
    expect(visibleChatStart(['user','assistant']), 0);
  });
  test('offline recovery uses the library and fits requested duration without network', () async {
    await LlmSettings.setCustomKey('test-key');
    final plan = await http.runWithClient(() => Api.generateRecovery(todayIso(), 23),
      () => MockClient((_) async => throw StateError('Offline must not call network')));
    expect(plan['source'], 'offline');
    final segments = plan['segments'] as List;
    expect(segments.fold<int>(0, (sum, s) => sum + (s['minutes'] as int)), 23);
    expect(segments.first['instruction'], contains('Spacer regeneracyjny'));
    expect(segments.last['instruction'], contains('Lekka mobilność'));
    expect(await LocalDb.list('events'), isEmpty);
  });
  test('online receives only executed last seven days including ratings and reflections', () async {
    final now = DateTime.now();
    String day(int offset) => dateIso(DateTime(now.year, now.month, now.day + offset));
    await LocalDb.saveList('trainings', [
      {'id': 'in', 'date': day(-6), 'duration_min': 50, 'rating': 4, 'went_well': 'Kontrola piłki', 'to_improve': 'Dokładność podań'},
      {'id': 'old', 'date': day(-7), 'duration_min': 60, 'went_well': 'OLD_SENTINEL'},
      {'id': 'future', 'date': day(1), 'duration_min': 60, 'went_well': 'FUTURE_SENTINEL'},
    ]);
    await LocalDb.saveList('matches', [{'id': 'm', 'date': day(-1), 'minutes_played': 65, 'rating': 0, 'to_improve': 'Koncentracja'}]);
    await LlmSettings.setCustomKey('test-key'); await LlmSettings.setMode('auto');
    String requestBody = '';
    final plan = await http.runWithClient(() => Api.generateRecovery(day(2), 20),
      () => MockClient((request) async {
        requestBody = utf8.decode(request.bodyBytes);
        return http.Response(jsonEncode({'candidates':[{'content':{'parts':[{'text':jsonEncode({
          'title':'Spokojny odpoczynek','description':'Po dwóch aktywnościach wybierz niską intensywność.',
          'segments':[{'minutes':12,'instruction':'Spaceruj spokojnie.'},{'minutes':8,'instruction':'Łagodna mobilność bez bólu.'}]
        })}]}}]}),200,headers:{'content-type':'application/json; charset=utf-8'});
      }));
    expect(plan['source'], 'online'); expect(plan['history_count'], 2);
    expect(requestBody, contains('Kontrola piłki')); expect(requestBody, contains('Dokładność podań'));
    expect(requestBody, contains('Koncentracja'));
    expect(requestBody, isNot(contains('OLD_SENTINEL'))); expect(requestBody, isNot(contains('FUTURE_SENTINEL')));
  });
  test('invalid AI duration falls back to an exact offline plan', () async {
    await LlmSettings.setCustomKey('test-key'); await LlmSettings.setMode('auto');
    final plan = await http.runWithClient(() => Api.generateRecovery(todayIso(), 20),
      () => MockClient((_) async => http.Response(jsonEncode({'candidates':[{'content':{'parts':[{'text':
        '{"title":"Test","description":"Test","segments":[{"minutes":100,"instruction":"Spacer"},{"minutes":5,"instruction":"Mobilność"}]}'}]}}]}),200)));
    expect(plan['source'], 'offline');
    expect((plan['segments'] as List).fold<int>(0, (sum,s) => sum+(s['minutes'] as int)),20);
  });
  test('plan, completion, edit, backup and deletion preserve one linked recovery', () async {
    final plan = await Api.generateRecovery(todayIso(), 20);
    final event = await Api.saveRecovery(plan);
    expect(event.type, 'recovery'); expect(event.done, isFalse);
    expect(await LocalDb.list('trainings'), isEmpty);
    final done = await Api.saveRecovery(plan,eventId:event.id,complete:true);
    await Api.saveRecovery(plan,eventId:event.id,complete:true);
    expect((await LocalDb.list('trainings')).length,1);
    final entry = (await Api.listTrainings()).single;
    expect(entry.kind, 'recovery');
    expect(await activityEditor(done), isA<RecoveryScreen>());
    await Api.saveRecovery({...plan, 'title':'Po edycji'}, trainingId:entry.id,complete:true);
    expect((await LocalDb.list('events')).length,1);
    final backup = await Api.exportBackup();
    expect(Api.inspectBackup(backup)['trainings'],1);
    await Api.importBackup(backup);
    final stats = await Api.progress();
    expect(stats.totalTrainings,0); expect(stats.totalMinutes,20);
    expect(stats.weekSessionTypes.last['recovery'],1);
    expect(stats.weekSessions.last,1);
    await Api.deleteEvent(done.id);
    expect(await LocalDb.list('trainings'),isEmpty);
    expect(await LocalDb.list('events'),isEmpty);
  });
  test('legacy notes remain notes and future completion is rejected', () async {
    final note = await Api.createEvent(date:todayIso(),type:'note',title:'Stara notatka',description:'Zachowaj');
    final now = DateTime.now();
    final plan = await Api.generateRecovery(dateIso(DateTime(now.year,now.month,now.day+1)),20);
    await expectLater(Api.saveRecovery(plan,complete:true),throwsA(isA<ApiException>()));
    expect((await Api.listEvents()).single.id,note.id);
    expect((await Api.listEvents()).single.type,'note');
  });
  testWidgets('planning recovery has only date and duration before generation', (tester) async {
    await tester.pumpWidget(shell(AddEventScreen(initialDate:todayIso())));
    await tester.tap(find.text('Regeneracja'));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryScreen),findsOneWidget);
    expect(find.text('Data'),findsOneWidget); expect(find.text('Czas (min)'),findsOneWidget);
    expect(find.text('Zaplanuj regenerację'),findsWidgets);
    expect(find.text('Intensywność'),findsNothing); expect(find.text('Oceń trening (opcjonalnie)'),findsNothing);
    expect(find.text('Notatka'),findsNothing);
    expect(find.byIcon(Icons.spa_outlined),findsWidgets);
    expect(tester.takeException(),isNull);
  });
  testWidgets('all four periods stay on a single line at small width and large font', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0,390.0]) {
      for (final scale in [1.0,1.4]) {
        await tester.binding.setSurfaceSize(Size(width,800));
        await tester.pumpWidget(MaterialApp(home: MediaQuery(data:MediaQueryData(textScaler:TextScaler.linear(scale)),
          child:Scaffold(body:Padding(padding:const EdgeInsets.all(20),child:PeriodSelector(value:30,onChanged:(_){}))))));
        await tester.pump();
        final offsets=[for(final id in [7,30,-1,0])tester.getTopLeft(find.byKey(ValueKey('period-$id'))).dy];
        expect(offsets.toSet().length,1);
        for(final text in ['7 dni','30 dni','Sezon','Cała historia']) { expect(find.text(text),findsOneWidget); }
        expect(tester.takeException(),isNull);
      }
    }
  });
  testWidgets('recovery appears in recent journal entries with purple spa icon', (tester) async {
    await tester.runAsync(() async {
      final plan=await Api.generateRecovery(todayIso(),20);
      await Api.saveRecovery(plan,complete:true);
    });
    final selected=ValueNotifier(0);
    await tester.pumpWidget(shell(DiaryScreen(selected:selected,index:0,onOpenCoach:(){})));
    await tester.pumpAndSettle();
    expect(find.text('Regeneracja'),findsWidgets);
    final icon=tester.widget<Icon>(find.byIcon(Icons.spa_outlined).first);
    expect(icon.color,Colors.white);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox()); selected.dispose();
  });
  testWidgets('exercise action has a visible primary background', (tester) async {
    await tester.pumpWidget(shell(ExerciseButton(label:'Zobacz ćwiczenia',onTap:(){})));
    expect(find.text('Zobacz ćwiczenia'),findsOneWidget);
    final materials=tester.widgetList<Material>(find.ancestor(of:find.text('Zobacz ćwiczenia'),matching:find.byType(Material)));
    expect(materials.any((m)=>m.color==AppColors.dark.brandPrimary),isTrue);
  });
}
