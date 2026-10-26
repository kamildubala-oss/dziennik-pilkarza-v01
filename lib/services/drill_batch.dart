import 'dart:math';
import '../models.dart';

/// Seven distinct local suggestions; consecutive batches never overlap.
class DrillBatch {
  DrillBatch({Random? random}) : _random = random ?? Random();
  final Random _random;
  List<Drill> _visible = [];

  List<Drill> current(List<Drill> library) {
    if (_visible.isEmpty && library.isNotEmpty) next(library);
    return List.unmodifiable(_visible);
  }

  void next(List<Drill> library) {
    final previous = _visible.map((d) => d.id).toSet();
    final unique = <String, Drill>{for (final d in library) d.id: d}.values.toList();
    final candidates = unique.where((d) => !previous.contains(d.id)).toList()..shuffle(_random);
    // Only libraries smaller than fourteen need to reuse some suggestions.
    if (candidates.length < 7) {
      candidates.addAll(unique.where((d) => previous.contains(d.id)).toList()..shuffle(_random));
    }
    _visible = candidates.take(7).toList();
  }
}
