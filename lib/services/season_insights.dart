import '../local_db.dart';
import '../utils.dart';
import 'match_stats.dart';
import 'progress_report.dart';

class CoveredMetric {
  const CoveredMetric(this.value, this.covered, this.total);
  final double? value;
  final int covered, total;
  String format({int decimals = 2, String suffix = ''}) => value == null ? '—' : '${value!.toStringAsFixed(decimals)}$suffix';
  String get coverage => '$covered/$total meczów z potrzebnymi danymi';
}

class MatchPeriod {
  MatchPeriod(this.matches);
  final List<Map<String, dynamic>> matches;
  int get count => matches.length;
  CoveredMetric sum(String key) {
    final values = matches.map((e) => MatchStats.value(e[key])).whereType<int>().toList();
    return CoveredMetric(values.isEmpty ? null : values.fold<int>(0,(a,b)=>a+b).toDouble(),values.length,count);
  }
  CoveredMetric perMatch(String key) {
    final total = sum(key);
    return CoveredMetric(total.covered == 0 ? null : total.value! / total.covered,total.covered,count);
  }
  CoveredMetric per90(String key) {
    final rows = matches.where((e) => MatchStats.value(e[key]) != null &&
      (MatchStats.value(e['minutes_played']) ?? -1) > 0).toList();
    final minutes = rows.fold<int>(0,(a,e)=>a+MatchStats.value(e['minutes_played'])!);
    return CoveredMetric(minutes == 0 ? null : rows.fold<int>(0,(a,e)=>a+MatchStats.value(e[key])!) * 90 / minutes,
      rows.length,count);
  }
  CoveredMetric accuracy(String part, String whole) {
    final rows = matches.map((e)=>MatchStats.fromJson(e['extra_stats'])).where((s)=>s[part]!=null && s[whole]!=null &&
      s[part]! <= s[whole]! && s[part]! >= 0 && s[whole]! >= 0).toList();
    final attempts = rows.fold<int>(0,(a,e)=>a+e[whole]!);
    return CoveredMetric(attempts == 0 ? null : rows.fold<int>(0,(a,e)=>a+e[part]!) * 100 / attempts,
      rows.length,count);
  }
  CoveredMetric average({bool legacy = false}) {
    final ratings = matches.where((e)=>!legacy || MatchStats.value(e['self_rating_10'])==null)
      .map((e)=>MatchStats.value(e[legacy ? 'rating' : 'self_rating_10']))
      .whereType<int>().where((r)=>r>=1 && r<=(legacy ? 5 : 10)).toList();
    return CoveredMetric(ratings.isEmpty ? null : ratings.fold<int>(0,(a,b)=>a+b)/ratings.length,ratings.length,count);
  }
}

class SeasonInsights {
  SeasonInsights(this.season, this.current, this.previous, this.seasonLabel, this.rangeLabel,
    this.previousRange, this.observations, this.asOf);
  final MatchPeriod season, current;
  final MatchPeriod? previous;
  final String seasonLabel, rangeLabel, previousRange;
  final List<Map<String,dynamic>> observations;
  final DateTime asOf;
  static Future<SeasonInsights> load(int period,{DateTime? asOf}) async => build(
    await LocalDb.list('matches'),await LocalDb.list('trainings'),period,asOf:asOf);
  static SeasonInsights build(List<Map<String,dynamic>> matches,List<Map<String,dynamic>> trainings,int period,{DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final today=DateTime(now.year,now.month,now.day);
    final end=dateIso(today), seasonStart=ProgressReport.startOfSeason(today);
    final start=period==0 ? null : period==-1 ? seasonStart : DateTime(today.year,today.month,today.day-period+1);
    bool included(Map<String,dynamic> e,String? from,String to) {
      final date=first10((e['date']??'').toString()), parsed=DateTime.tryParse(first10((e['date']??'').toString()));
      return parsed!=null && dateIso(parsed)==date && date.compareTo(to)<=0 && (from==null || date.compareTo(from)>=0);
    }
    final all=matches.where((e)=>included(e,null,end)).toList()..sort((a,b)=>a['date'].toString().compareTo(b['date'].toString()));
    final current=all.where((e)=>included(e,start==null?null:dateIso(start),end)).toList();
    MatchPeriod? previous;
    var previousRange='';
    if(start!=null) {
      final days=DateTime.utc(today.year,today.month,today.day).difference(DateTime.utc(start.year,start.month,start.day)).inDays+1;
      final from=dateIso(DateTime(start.year,start.month,start.day-days)),to=dateIso(DateTime(start.year,start.month,start.day-1));
      previous=MatchPeriod(all.where((e)=>included(e,from,to)).toList()); previousRange='$from – $to';
    }
    final observations=[...current,...trainings.where((e)=>e['kind']!='recovery' && included(e,start==null?null:dateIso(start),end))]
      ..sort((a,b)=>b['date'].toString().compareTo(a['date'].toString()));
    return SeasonInsights(MatchPeriod(all.where((e)=>included(e,dateIso(seasonStart),end)).toList()),
      MatchPeriod(current),previous,'${seasonStart.year}/${seasonStart.year+1}',
      '${start==null?'Początek historii':dateIso(start)} – $end',previousRange,observations,today);
  }
  List<Map<String,dynamic>> get ratingSeries => current.matches.where((e){
    final v=MatchStats.value(e['self_rating_10']);return v!=null && v>=1 && v<=10;
  }).toList();
  String get formSummary {
    final avg=current.average(), before=previous?.average();
    if(avg.covered==0) return 'Brak samoocen meczów w skali 1–10. Historyczne oceny 1–5 pozostają osobno.';
    if(avg.covered<2 || before==null || before.covered<2) return 'Średnia samoocena ${avg.format(decimals:1)}/10 z ${avg.covered} ocen. '
      'Do porównania trendu potrzebne są co najmniej dwie oceny w każdym okresie.';
    final diff=avg.value!-before.value!;
    return 'Średnia samoocena ${avg.format(decimals:1)}/10: ${diff.abs()<.05?'bez wyraźnej zmiany':diff>0?'wyższa o ${diff.toStringAsFixed(1)}':'niższa o ${(-diff).toStringAsFixed(1)}'} '
      'w porównaniu z poprzednim okresem (${avg.covered} i ${before.covered} ocen). To trend odczuć zawodnika, nie obiektywny pomiar umiejętności.';
  }
  List<String> quotes(String key) => observations.where((e)=>(e[key]??'').toString().trim().isNotEmpty)
    .take(3).map((e)=>'${first10(e['date'].toString())}: ${(e[key]??'').toString().trim()}').toList();
  String? get suggestedArea {
    final texts=observations.map((e)=>(e['to_improve']??'').toString().toLowerCase()).toList();
    const terms={'Technika':['podani','przyję','prowadz'],'Strzał':['strzał','celność strza'],
      'Taktyka':['ustaw','decyz','przechwyt'],'Motoryka':['szybko','wytrzym'],'Mentalność':['koncentr','pewno']};
    for(final e in terms.entries) { if(texts.where((text)=>e.value.any(text.contains)).length>=2)return e.key; }
    return null;
  }
  List<String> get nextSteps => [
    if(current.sum('minutes_played').covered < current.count) 'Uzupełnij czas gry w meczach bez minut — umożliwi to rzetelne wskaźniki na 90 minut.',
    if(suggestedArea!=null) 'W co najmniej dwóch obserwacjach wraca obszar: $suggestedArea. Wybierz jedno ćwiczenie i omów je z trenerem.',
    if(current.average().covered<2) 'Po kolejnych meczach zapisz krótką samoocenę 1–10; nie uzupełniaj jej automatycznie.',
    'Po następnym meczu zanotuj jedną rzecz, która wyszła dobrze, i jedną do poprawy.',
  ];
  String get reportText {
    final good=quotes('went_well'), improve=quotes('to_improve');
    return 'RAPORT FORMY · ${dateIso(asOf)}\nZakres: $rangeLabel\nŹródło: lokalne podsumowanie zapisanych danych.\n\n'
      'PODSUMOWANIE\n$formSummary\nMecze: ${current.count}\n'
      'Gole na mecz: ${current.perMatch('goals').format()} (${current.perMatch('goals').coverage})\n'
      'Asysty na mecz: ${current.perMatch('assists').format()} (${current.perMatch('assists').coverage})\n'
      'Gole/90 min: ${current.per90('goals').format()} (${current.per90('goals').coverage})\n'
      'Asysty/90 min: ${current.per90('assists').format()} (${current.per90('assists').coverage})\n\n'
      'MOCNE STRONY — TWOJE OBSERWACJE\n${good.isEmpty?'Brak obserwacji.':good.join('\n')}\n\n'
      'OBSZARY DO POPRAWY — TWOJE OBSERWACJE\n${improve.isEmpty?'Brak obserwacji.':improve.join('\n')}\n\n'
      'NASTĘPNE KROKI\n${nextSteps.map((s)=>'- $s').join('\n')}';
  }
}
