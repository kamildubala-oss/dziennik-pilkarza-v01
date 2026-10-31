import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/season_insights.dart';
import '../theme.dart';
import '../utils.dart';
import 'common.dart';
import 'exercise_button.dart';

class SeasonInsightsPanel extends StatelessWidget {
  const SeasonInsightsPanel({super.key,required this.data,required this.onExercises});
  final SeasonInsights data;
  final ValueChanged<String> onExercises;
  @override
  Widget build(BuildContext context) {
    final c=context.c, season=data.season;
    Widget metric(String label,CoveredMetric value,{String suffix=''}) => Padding(
      padding:const EdgeInsets.symmetric(vertical:6),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(label,style:manrope(size:13,color:c.onSurface)),
          Text(value.coverage,style:manrope(size:10,color:c.muted)),
        ])),const SizedBox(width:8),Text(value.format(suffix:suffix),style:barlow(size:23,color:c.onSurface)),
      ]));
    String difference(CoveredMetric current,CoveredMetric? previous) {
      if(current.value==null || previous?.value==null)return 'Brak kompletnych danych do porównania';
      final delta=current.value!-previous!.value!;
      return '${delta>=0?'+':''}${delta.toStringAsFixed(2)} · dane z ${current.covered} / ${previous.covered} meczów';
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const SizedBox(height:Sp.lg),
      SectionTitle('SEZON ${data.seasonLabel}'),
      Text('Od 1 lipca · ${season.count} zapisanych meczów. „—” oznacza brak danych, nie zero.',
        style:manrope(size:11,color:c.muted)),
      Container(margin:const EdgeInsets.only(top:8),padding:const EdgeInsets.all(Sp.md),
        decoration:BoxDecoration(color:c.surfaceSecondary,borderRadius:BorderRadius.circular(Rad.md)),
        child:Column(children:[
          metric('Gole na mecz',season.perMatch('goals')),
          metric('Asysty na mecz',season.perMatch('assists')),
          metric('Gole na 90 min',season.per90('goals')),
          metric('Asysty na 90 min',season.per90('assists')),
          metric('Samoocena 1–10',season.average(),suffix:'/10'),
          if(season.average(legacy:true).covered>0) metric('Historyczna samoocena 1–5',season.average(legacy:true),suffix:'/5'),
          metric('Celność strzałów',season.accuracy('shots_on_target','shots'),suffix:'%'),
          metric('Celność podań',season.accuracy('passes_completed','passes_attempted'),suffix:'%'),
        ])),
      Text('Wskaźniki obejmują tylko mecze z potrzebnymi danymi. Na 90 minut: suma wyników / suma minut × 90 '
        'w tej samej grupie meczów; czas gry musi być większy od zera. Procenty: suma celnych / suma wszystkich prób '
        'z kompletnych par, bez uśredniania procentów pojedynczych meczów.',style:manrope(size:10,color:c.muted)),
      const SizedBox(height:Sp.md),const SectionTitle('TRENDY I PORÓWNANIE MECZÓW'),
      Text(data.rangeLabel,style:manrope(size:11,color:c.muted)),
      Text(data.formSummary,style:manrope(size:13,height:1.4,color:c.onSurface)),
      if(data.previous!=null) ...[
        Text('Poprzedni okres: ${data.previousRange}',style:manrope(size:11,color:c.muted)),
        metric('Gole/mecz · bieżący okres',data.current.perMatch('goals')),
        Text('Zmiana: ${difference(data.current.perMatch('goals'),data.previous!.perMatch('goals'))}',style:manrope(size:11,color:c.muted)),
        metric('Asysty/mecz · bieżący okres',data.current.perMatch('assists')),
        Text('Zmiana: ${difference(data.current.perMatch('assists'),data.previous!.perMatch('assists'))}',style:manrope(size:11,color:c.muted)),
        metric('Gole/90 min · bieżący okres',data.current.per90('goals')),
        Text('Zmiana: ${difference(data.current.per90('goals'),data.previous!.per90('goals'))}',style:manrope(size:11,color:c.muted)),
        metric('Asysty/90 min · bieżący okres',data.current.per90('assists')),
        Text('Zmiana: ${difference(data.current.per90('assists'),data.previous!.per90('assists'))}',style:manrope(size:11,color:c.muted)),
      ],
      if(data.ratingSeries.isNotEmpty) ...[
        const SizedBox(height:8),Text('Ostatnie samooceny meczów · skala 1–10',style:manrope(size:11,color:c.muted)),
        SizedBox(height:160,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          for(final match in data.ratingSeries.skip(data.ratingSeries.length>6?data.ratingSeries.length-6:0))
            Expanded(child:Semantics(label:'${first10(match['date'].toString())}: ${match['self_rating_10']}/10',
              child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[
                Text('${match['self_rating_10']}',style:manrope(size:11,color:c.onSurface)),
                Container(width:14,height:(match['self_rating_10'] as num).toDouble()*8,color:c.brandPrimary),
                const SizedBox(height:4),FittedBox(child:Text(first10(match['date'].toString()).substring(5),style:manrope(size:10,color:c.muted))),
              ]))),
        ])),
      ],
      const SizedBox(height:Sp.lg),
      ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('Raport formy'),
        subtitle:const Text('Podsumowanie · mocne strony · obszary do poprawy · następne kroki'),
        children:[
          Text('Lokalne podsumowanie wpisów · ${data.rangeLabel}',style:manrope(size:11,color:c.muted)),
          SelectableText(data.reportText,style:manrope(size:13,height:1.45,color:c.onSurface)),
          if(data.suggestedArea!=null) ExerciseButton(onTap:()=>onExercises(data.suggestedArea!),label:'Zobacz ćwiczenia'),
          TextButton.icon(onPressed:() async {
            await Clipboard.setData(ClipboardData(text:data.reportText));
            if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Raport skopiowany')));
          },icon:const Icon(Icons.copy),label:const Text('Kopiuj raport')),
        ]),
    ]);
  }
}
