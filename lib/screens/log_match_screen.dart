import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../services/match_stats.dart';
import '../services/user_errors.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';

/// Modal "Zapisz mecz".
class LogMatchScreen extends StatefulWidget {
  const LogMatchScreen({
    super.key,
    this.initialDate,
    this.title,
    this.header,
    this.plannedEventId,
    this.editing,
    this.editingEvent,
    this.completingEvent,
    this.isPlanned = false,
  });

  /// Edytowany mecz (tryb edycji). Gdy null - nowy wpis.
  final MatchEntry? editing;
  final EventItem? editingEvent;
  /// Kalendarz: wykonujemy wcześniej zaplanowany mecz, a nie edytujemy planu.
  final EventItem? completingEvent;

  /// Zaplanowany mecz z kalendarza, który właśnie się odbył.
  final String? plannedEventId;

  /// True, gdy zapisujemy plan z kalendarza, a nie wykonaną już aktywność.
  final bool isPlanned;

  /// Data początkowa (RRRR-MM-DD). Domyślnie dzisiaj.
  final String? initialDate;

  /// Tytuł okna. Domyślnie jak w dzienniku.
  final String? title;

  /// Dodatkowa sekcja na górze formularza (np. wybór typu w kalendarzu).
  final Widget? header;

  @override
  State<LogMatchScreen> createState() => _LogMatchScreenState();
}

class _LogMatchScreenState extends State<LogMatchScreen> {
  late final MatchEntry? _e = widget.editing;
  late final EventItem? _sourceEvent = widget.completingEvent ?? widget.editingEvent;
  late final TextEditingController _date = TextEditingController(
    text: _e != null ? first10(_e.date) : (_sourceEvent?.date ?? widget.initialDate ?? todayIso()),
  );
  late final TextEditingController _opponent =
      TextEditingController(text: _e?.opponent ?? (_sourceEvent?.details['opponent'] as String?) ?? '');
  late final TextEditingController _result =
      TextEditingController(text: _e?.result ?? (_sourceEvent?.details['result'] as String?) ?? '');
  late final TextEditingController _minutes =
      TextEditingController(text: '${_e?.minutesPlayed ?? _sourceEvent?.details['minutes_played'] ?? ''}');
  late final TextEditingController _goals =
      TextEditingController(text: '${_e?.goals ?? _sourceEvent?.details['goals'] ?? ''}');
  late final TextEditingController _assists =
      TextEditingController(text: '${_e?.assists ?? _sourceEvent?.details['assists'] ?? ''}');
  late final TextEditingController _wentWell =
      TextEditingController(text: _e?.wentWell ?? (_sourceEvent?.details['went_well'] as String?) ?? '');
  late final TextEditingController _toImprove =
      TextEditingController(text: _e?.toImprove ?? (_sourceEvent?.details['to_improve'] as String?) ?? '');
  late final String _preservedNotes =
      _e?.notes ?? (_sourceEvent?.details['notes'] as String?) ?? '';

  bool get _planning => _e == null && widget.completingEvent == null &&
      (widget.isPlanned || widget.editingEvent != null);

  late int _rating = _e != null && _e.rating >= 0 ? _e.rating : (_sourceEvent?.details['rating'] as int?) ?? 0;
  late int? _selfRating10 = _e?.selfRating10 ?? MatchStats.value(_sourceEvent?.details['self_rating_10']);
  late final Map<String, TextEditingController> _extra = {
    for (final key in MatchStats.labels.keys) key: TextEditingController(
      text: '${_e?.extraStats[key] ?? MatchStats.fromJson(_sourceEvent?.details['extra_stats'])[key] ?? ''}'),
  };
  Map<String, int?> get _extraValues => {for (final e in _extra.entries) e.key: int.tryParse(e.value.text.trim())};
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _extra.values) { controller.dispose(); }
    _date.dispose();
    _opponent.dispose();
    _result.dispose();
    _minutes.dispose();
    _goals.dispose();
    _assists.dispose();
    _wentWell.dispose();
    _toImprove.dispose();
    super.dispose();
  }

  int? _num(TextEditingController c) => int.tryParse(c.text.trim());
  String? _numberError(TextEditingController c, String label, int max) =>
    c.text.trim().isEmpty ? null : numberFieldError(c.text, label, 0, max);
  bool get _fieldsValid => _planning || (
      _numberError(_minutes, 'Minuty', 180) == null &&
      _numberError(_goals, 'Gole', 20) == null &&
      _numberError(_assists, 'Asysty', 20) == null &&
      _extra.entries.every((e) => _numberError(e.value, MatchStats.labels[e.key]!, 2000) == null) &&
      MatchStats.error(_extraValues) == null);

  Future<void> _save() async {
    if (_saving || !_fieldsValid) return;
    setState(() => _saving = true);
    try {
      if (_planning) {
        final opponent = _opponent.text.trim();
        final title = opponent.isEmpty ? 'Mecz' : 'Mecz z $opponent';
        if (widget.editingEvent != null) {
          await Api.updatePlannedActivity(widget.editingEvent!.id,
            date: _date.text, title: title, description: opponent.isEmpty ? '' : 'Rywal: $opponent',
            details: <String, dynamic>{'opponent': opponent});
        } else {
          await Api.createEvent(date: _date.text, type: 'match', title: title,
            description: opponent.isEmpty ? '' : 'Rywal: $opponent',
            details: <String, dynamic>{'opponent': opponent});
        }
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final e = _e;
      if (e != null) {
        await Api.updateMatch(
          e.id,
          date: _date.text,
          opponent: _opponent.text,
          result: _result.text,
          minutesPlayed: _num(_minutes),
          goals: _num(_goals),
          assists: _num(_assists),
          rating: _rating,
          wentWell: _wentWell.text,
          toImprove: _toImprove.text,
          notes: _preservedNotes,
          selfRating10: _selfRating10, clearSelfRating10: _selfRating10 == null, extraStats: _extraValues,
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await Api.createMatch(
        date: _date.text,
        opponent: _opponent.text,
        result: _result.text,
        minutesPlayed: _num(_minutes),
        goals: _num(_goals),
        assists: _num(_assists),
        rating: _rating,
        wentWell: _wentWell.text,
        toImprove: _toImprove.text,
        notes: _preservedNotes,
        selfRating10: _selfRating10, extraStats: _extraValues,
        plannedEventId: widget.completingEvent?.id ?? widget.plannedEventId,
        isPlanned: widget.isPlanned,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error))));
        setState(() => _saving = false);
      }
    }
  }

  Widget _number(String label, TextEditingController controller, int max) => LabeledField(
    label: label, child: AppTextField(controller: controller, keyboardType: TextInputType.number,
      hint: '—', errorText: _numberError(controller, label, max), onChanged: (_) => setState(() {})));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(backgroundColor: c.surface, body: Column(children: [
      ModalHeader(title: widget.title ?? (_e != null || widget.editingEvent != null
        ? 'Edytuj mecz' : _planning ? 'Zaplanuj mecz' : 'Zapisz mecz'),
        onClose: () => Navigator.of(context).pop()),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.header != null && _e == null && widget.editingEvent == null &&
              widget.completingEvent == null) widget.header!,
          LabeledField(label:'Data', child:DateField(controller:_date)),
          LabeledField(label:'Przeciwnik', child:AppTextField(controller:_opponent, hint:'np. Legia U15')),
          if (!_planning) ...[
            LabeledField(label:'Wynik', child:AppTextField(controller:_result, hint:'np. 3:1 (opcjonalnie)')),
            Row(crossAxisAlignment:CrossAxisAlignment.start, children:[
              Expanded(child:_number('Minuty',_minutes,180)), const SizedBox(width:Sp.sm),
              Expanded(child:_number('Gole',_goals,20)), const SizedBox(width:Sp.sm),
              Expanded(child:_number('Asysty',_assists,20)),
            ]),
            Text('Puste pole = brak danych. Wpisz 0 tylko wtedy, gdy znasz wynik.',
              style:manrope(size:11,color:c.muted)),
            const SizedBox(height:Sp.md),
            const FieldLabel('Jak oceniasz swój mecz?'),
            Text('Samoocena 1–10 (opcjonalnie)', style:manrope(size:12,color:c.muted)),
            Wrap(spacing:4,runSpacing:4,children:[
              for (var n=1;n<=10;n++) Semantics(selected:_selfRating10==n,button:true,
                child:ChoiceChip(label:Text('$n'),selected:_selfRating10==n,
                  onSelected:(_) => setState(() => _selfRating10 = _selfRating10==n ? null : n))),
            ]),
            if (_selfRating10!=null) TextButton(onPressed:()=>setState(()=>_selfRating10=null),
              child:const Text('Usuń samoocenę')),
            if (_rating>0) Text('Zachowana historyczna ocena: $_rating/5. Nie jest przeliczana na skalę 1–10.',
              style:manrope(size:11,color:c.muted)),
            ExpansionTile(key:const ValueKey('extra-match-stats'),initiallyExpanded:false,maintainState:true,
              tilePadding:EdgeInsets.zero,title:const Text('Dodatkowe statystyki'),
              subtitle:const Text('Opcjonalne · możesz uzupełnić później'),
              children:[
                for (final e in MatchStats.labels.entries) _number(e.value,_extra[e.key]!,2000),
                if (MatchStats.error(_extraValues)!=null) Text(MatchStats.error(_extraValues)!,
                  style:manrope(size:12,color:c.error)),
              ]),
            LabeledField(label:'Co było dobrze?',child:AppTextField(controller:_wentWell,multiline:true,minLines:2,
              hint:'Opcjonalnie — możesz dopisać później')),
            LabeledField(label:'Co poprawić?',child:AppTextField(controller:_toImprove,multiline:true,minLines:2,
              hint:'Opcjonalnie — jedna konkretna obserwacja')),
          ],
        ]))),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(Sp.lg,Sp.sm,Sp.lg,Sp.sm),
        child:PrimaryButton(label:_saving ? 'Zapisywanie...' : _e!=null || widget.editingEvent!=null
          ? 'Zapisz zmiany' : widget.completingEvent!=null ? 'Mecz wykonany' : _planning ? 'Zaplanuj mecz' : 'Zapisz mecz',
          onTap:_saving || !_fieldsValid ? null : _save))),
    ]));
  }
}
