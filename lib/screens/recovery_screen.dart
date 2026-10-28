import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../services/coach_runtime.dart';
import '../services/user_errors.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, this.initialDate, this.event, this.editingTraining,
    this.complete = false, this.header});
  final String? initialDate;
  final EventItem? event;
  final Training? editingTraining;
  final bool complete;
  final Widget? header;
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  late final _date = TextEditingController(text: widget.editingTraining?.date ??
    (widget.event != null ? first10(widget.event!.date) : widget.initialDate ?? todayIso()));
  late final _duration = TextEditingController(text:
    '${widget.editingTraining?.durationMin ?? (widget.event != null && widget.event!.durationMin > 0 ? widget.event!.durationMin : 20)}');
  Map<String, dynamic>? _plan;
  bool _loading = true, _busy = false;
  bool get _execution => widget.complete || widget.editingTraining != null;
  @override
  void initState() {
    super.initState();
    _date.addListener(_changed);
    _duration.addListener(_changed);
    _load();
  }
  Future<void> _load() async {
    try {
      final record = widget.editingTraining == null ? null : await Api.recoveryRecord(widget.editingTraining!.id);
      final raw = record?['recovery_plan'] ?? widget.event?.details['recovery_plan'];
      if (mounted) setState(() { _plan = raw is Map ? Map<String, dynamic>.from(raw) : null; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); _error(e); }
    }
  }
  void _changed() {
    if (mounted && !_loading) setState(() => _plan = null);
  }
  @override
  void dispose() {
    _date.dispose(); _duration.dispose();
    super.dispose();
  }
  void _error(Object e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  Future<void> _generate() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final minutes = int.tryParse(_duration.text.trim()) ?? 0;
      final plan = await Api.generateRecovery(_date.text, minutes);
      if (mounted) setState(() => _plan = plan);
    } catch (e) { if (mounted) _error(e); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _save() async {
    if (_busy || _plan == null) return;
    setState(() => _busy = true);
    try {
      await Api.saveRecovery(_plan!, eventId: widget.event?.id,
        trainingId: widget.editingTraining?.id, complete: _execution);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) { _error(e); setState(() => _busy = false); } }
  }
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final plan = _plan;
    final raw = plan?['segments'];
    final segments = raw is List ? raw.whereType<Map>().toList() : <Map>[];
    return Scaffold(backgroundColor: c.surface, body: Column(children: [
      ModalHeader(title: widget.editingTraining != null ? 'Edytuj regenerację'
        : _execution ? 'Zapisz regenerację' : 'Zaplanuj regenerację', onClose: () => Navigator.pop(context)),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(Sp.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.header != null) widget.header!,
          const FieldLabel('Data'),
          IgnorePointer(ignoring: _busy, child: DateField(controller: _date)),
          const SizedBox(height: Sp.lg),
          const FieldLabel('Czas (min)'),
          IgnorePointer(ignoring: _busy, child: AppTextField(controller: _duration, keyboardType: TextInputType.number, hint: '20')),
          Text('Od 5 do 120 minut spokojnej aktywności.', style: manrope(size: 11, color: c.muted)),
          PrimaryButton(label: _busy ? 'Przygotowywanie…' : plan == null ? 'Zaplanuj regenerację' : 'Generuj ponownie',
            icon: Icons.spa_outlined, marginTop: Sp.lg, onTap: _busy || _loading ? null : _generate),
          if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: Spinner())),
          if (plan != null) ...[
            const SizedBox(height: Sp.lg),
            Text('${CoachRuntime.sourceLabel((plan['source'] ?? '').toString())}\n'
              'Utworzono: ${CoachRuntime.dateLabel((plan['generated_at'] ?? '').toString())}',
              style: manrope(size: 11, color: c.muted)),
            if ((plan['fallback_reason'] ?? '').toString().isNotEmpty)
              Text(plan['fallback_reason'].toString(), style: manrope(size: 12, color: c.muted)),
            Text('Na podstawie wpisów: ${plan['history_from']} – ${plan['history_to']}',
              style: manrope(size: 11, color: c.muted)),
            const SizedBox(height: Sp.md),
            Text(plan['title'].toString(), style: barlow(size: 25, color: c.onSurface)),
            Text(plan['description'].toString(), style: manrope(size: 13, height: 1.4, color: c.muted)),
            for (var i = 0; i < segments.length; i++) Container(
              margin: const EdgeInsets.only(top: Sp.sm), padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(color: c.surfaceSecondary, borderRadius: BorderRadius.circular(Rad.md)),
              child: Text('${i + 1}. ${segments[i]['minutes']} min\n${segments[i]['instruction']}',
                style: manrope(size: 14, height: 1.4, color: c.onSurface))),
            PrimaryButton(label: widget.editingTraining != null || widget.event != null && !_execution
                ? 'Zapisz zmiany' : _execution ? 'Zapisz regenerację' : 'Zapisz w kalendarzu',
              marginTop: Sp.lg, onTap: _busy ? null : _save),
          ],
        ]))),
    ]));
  }
}
