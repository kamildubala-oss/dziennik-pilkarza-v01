import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/services/match_stats.dart';
import 'package:dziennik_pilkarza/services/season_insights.dart';
import 'package:dziennik_pilkarza/screens/log_match_screen.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:dziennik_pilkarza/widgets/season_insights_panel.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(()async{SharedPreferences.setMockInitialValues({});await LocalDb.list('matches');});
  setUp(()async{for(final key in ['matches','trainings','events','plans']) {await LocalDb.saveList(key,[]);}});
  Map<String,dynamic> row(String date,{int? goals,int? assists,int? minutes,int? score,int legacy=0,Map<String,int?> extra=const{}})=>{
    'date':date,'goals':goals,'assists':assists,'minutes_played':minutes,'self_rating_10':score,'rating':legacy,'extra_stats':extra};
  test('rates use matched observations, preserve zero and reject missing denominators',(){
    final stats=MatchPeriod([
      row('2026-10-20',goals:2,assists:0,minutes:45),
      row('2026-10-21',goals:0,assists:1,minutes:90),
      row('2026-10-22',goals:null,assists:null,minutes:60),
      row('2026-10-23',goals:4,minutes:null),
      row('2026-10-24',goals:0,minutes:0),
    ]);
    expect(stats.perMatch('goals').value,1.5);expect(stats.perMatch('goals').covered,4);
    expect(stats.per90('goals').value,closeTo(2*90/135,1e-9));expect(stats.per90('goals').covered,2);
    expect(stats.per90('assists').value,closeTo(90/135,1e-9));
    expect(MatchPeriod([row('2026-10-20')]).per90('goals').value,isNull);
    expect(MatchPeriod([row('2026-10-20',goals:0,minutes:0)]).per90('goals').value,isNull);
  });
  test('accuracy needs both fields, aggregates attempts and handles 0/0 as unknown',(){
    final stats=MatchPeriod([
      row('2026-10-20',extra:{'shots':2,'shots_on_target':1,'passes_completed':20}),
      row('2026-10-21',extra:{'shots':8,'shots_on_target':2,'passes_attempted':30}),
      row('2026-10-22',extra:{'shots':100}),
    ]);
    expect(stats.accuracy('shots_on_target','shots').value,30);
    expect(stats.accuracy('shots_on_target','shots').covered,2);
    expect(stats.accuracy('passes_completed','passes_attempted').value,isNull);
    expect(MatchPeriod([row('2026-10-20',extra:{'shots':0,'shots_on_target':0})]).accuracy('shots_on_target','shots').value,isNull);
    expect(MatchStats.error({'shots':2,'shots_on_target':3}),isNotNull);
    expect(MatchStats.error({'passes_completed':20,'passes_attempted':10}),isNotNull);
    expect(MatchStats.error({'shots_on_target':2,'shots':null}),isNull);
  });
  test('season and comparison respect July boundary, future dates and independent rating scales',(){
    final data=SeasonInsights.build([
      row('2026-06-30',goals:50),row('2026-07-01',goals:1,legacy:5),
      row('2026-10-15',score:6),row('2026-10-16',score:6),
      row('2026-10-22',score:8),row('2026-10-28',score:8),row('2026-10-29',goals:99,score:10),
    ],[],7,asOf:DateTime(2026,10,28));
    expect(data.season.count,5);expect(data.current.count,2);expect(data.previous!.count,2);
    expect(data.season.sum('goals').value,1);
    expect(data.current.average().value,8);expect(data.season.average(legacy:true).value,5);
    expect(data.formSummary,contains('wyższa o 2.0'));
    expect(data.reportText,contains('MOCNE STRONY'));
    expect(data.reportText,contains('NASTĘPNE KROKI'));
  });
  test('a single rating cannot establish form trend, reports quote actual observations',(){
    final data=SeasonInsights.build([
      {...row('2026-10-28',score:8),'went_well':'Dobre przyjęcie','to_improve':'Podania słabszą nogą'},
    ],[{'date':'2026-10-27','to_improve':'Dokładność podań'}],30,asOf:DateTime(2026,10,28));
    expect(data.formSummary,contains('co najmniej dwie oceny'));
    expect(data.reportText,contains('Dobre przyjęcie'));
    expect(data.suggestedArea,'Technika');
  });
  test('new nullable statistics survive edit, linked calendar, JSON and CSV',()async{
    final match=await Api.createMatch(date:todayIso(),opponent:'Skra',result:'',minutesPlayed:null,goals:null,assists:0,
      rating:0,selfRating10:8,extraStats:{'shots':null,'shots_on_target':0,'passes_completed':null},wentWell:'',toImprove:'',notes:'');
    expect(match.minutesPlayed,isNull);expect(match.goals,isNull);expect(match.assists,0);expect(match.selfRating10,8);
    final backup=await Api.exportBackup();await Api.importBackup(backup);
    final restored=(await Api.listMatches()).single;
    expect(restored.goals,isNull);expect(restored.extraStats['shots'],isNull);
    await Api.updateMatch(restored.id,date:todayIso(),opponent:'Skra',result:'',minutesPlayed:60,goals:1,assists:null,
      rating:0,selfRating10:9,extraStats:{'shots':4,'shots_on_target':2},wentWell:'',toImprove:'',notes:'');
    final event=(await LocalDb.list('events')).single;
    expect(event['self_rating_10'],9);expect(event['assists'],isNull);expect(event['extra_stats']['shots'],4);
    final csv=await Api.exportMatchesCsv();expect(csv,contains('Samoocena (1-10)'));expect(csv,contains('Strzały celne'));
    final raw=jsonDecode(await Api.exportBackup());expect(raw['data']['matches'][0]['assists'],isNull);
    await Api.updateMatch(restored.id,date:todayIso(),opponent:'Skra',result:'',minutesPlayed:null,goals:null,assists:null,
      rating:0,clearSelfRating10:true,extraStats:{'shots':null,'shots_on_target':null},wentWell:'',toImprove:'',notes:'');
    final cleared=(await Api.listMatches()).single;
    expect(cleared.selfRating10,isNull);expect(cleared.extraStats['shots'],isNull);expect(cleared.minutesPlayed,isNull);

  });
  test('invalid relationships and self-rating cannot enter through import',(){
    final backup={'app':'dziennik_pilkarza','version':1,'data':{'matches':[{
      'id':'bad','date':todayIso(),'self_rating_10':11,'extra_stats':{'shots':1,'shots_on_target':3}}]}};
    expect(()=>Api.inspectBackup(jsonEncode(backup)),throwsA(isA<ApiException>()));
    backup['data']={'matches':[{'id':'good','date':todayIso(),'minutes_played':null,'goals':null,'assists':0,'self_rating_10':null,'extra_stats':{'shots':null}}]};
    expect(Api.inspectBackup(jsonEncode(backup))['matches'],1);
  });
  testWidgets('quick match save leaves unknown fields null and advanced section collapsed',(tester)async{
    await tester.pumpWidget(MaterialApp(home:const LogMatchScreen()));
    final tile=tester.widget<ExpansionTile>(find.byKey(const ValueKey('extra-match-stats')));
    expect(tile.initiallyExpanded,isFalse);
    expect(find.text('Strzały').hitTestable(),findsNothing);
    final opponent=find.descendant(of:find.byWidgetPredicate((w)=>w is AppTextField && w.hint=='np. Legia U15'),matching:find.byType(TextField));
    await tester.enterText(opponent,'Skra');
    await tester.runAsync(()async{await tester.tap(find.byType(PrimaryButton));await LocalDb.synchronized<void>(()async{});});
    await tester.pumpAndSettle();
    final raw=(await LocalDb.list('matches')).single;
    for(final key in ['goals','assists','minutes_played','self_rating_10']) {expect(raw[key],isNull,reason:key);}
    expect(raw['extra_stats']['shots'],isNull);
    expect(tester.takeException(),isNull);
  });
  testWidgets('season report panel renders on a narrow screen without overflow',(tester)async{
    addTearDown(()=>tester.binding.setSurfaceSize(null));await tester.binding.setSurfaceSize(const Size(320,850));
    final data=SeasonInsights.build([row(todayIso(),goals:1,assists:0,minutes:60,score:8)],[],30);
    await tester.pumpWidget(MaterialApp(theme:buildTheme(AppColors.dark,Brightness.dark),home:Scaffold(
      body:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(20),child:SeasonInsightsPanel(data:data,onExercises:(_){}))))));
    await tester.pumpAndSettle();
    expect(find.text('Gole na 90 min'),findsOneWidget);expect(find.text('Raport formy'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
