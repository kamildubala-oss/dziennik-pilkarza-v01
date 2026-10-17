import '../models.dart';
import '../utils.dart';

/// Pola formularza wykonania odczytane z zaplanowanego wydarzenia.
/// Nowe plany zapisują dane strukturalne, starsze mogą mieć je tylko w opisie.
class PlannedTrainingDefaults {
  const PlannedTrainingDefaults({
    required this.date,
    required this.durationMin,
    required this.focuses,
    required this.intensity,
    required this.rating,
    required this.wentWell,
    required this.toImprove,
    required this.notes,
  });

  final String date;
  final int? durationMin;
  final List<String> focuses;
  final String intensity;
  final int rating;
  final String wentWell;
  final String toImprove;
  final String notes;

  static String _text(dynamic value) =>
      value == null ? '' : value.toString().trim();

  static String _descriptionField(String description, List<String> labels) {
    for (final line in description.split('\n')) {
      final trimmed = line.trim();
      for (final label in labels) {
        if (trimmed.toLowerCase().startsWith(label.toLowerCase())) {
          return trimmed.substring(label.length).trim();
        }
      }
    }
    return '';
  }

  static int? _positiveNumber(dynamic value) {
    final number = value is num ? value.toInt() : int.tryParse(_text(value));
    return number != null && number > 0 ? number : null;
  }

  factory PlannedTrainingDefaults.fromEvent(EventItem event) {
    final details = event.details;
    final description = event.description;

    final rawFocuses = details['focuses'];
    var focuses = rawFocuses is List
        ? rawFocuses.map(_text).where((f) => f.isNotEmpty).toList()
        : <String>[];
    if (focuses.isEmpty) {
      final focus = _text(details['focus']).isNotEmpty
          ? _text(details['focus'])
          : event.focus.isNotEmpty
          ? event.focus
          : _descriptionField(description, <String>['Obszary:']);
      focuses = focus
          .split(',')
          .map((f) => f.trim())
          .where((f) => f.isNotEmpty)
          .toList();
    }

    final savedDuration = _positiveNumber(details['duration_min']);
    final legacyDurationText = _descriptionField(description, <String>[
      'Czas:',
    ]);
    final legacyDurationMatch = RegExp(r'\d+').firstMatch(legacyDurationText);
    final legacyDuration = legacyDurationMatch == null
        ? null
        : int.tryParse(legacyDurationMatch.group(0)!);

    final rawIntensity = _text(details['intensity']).isNotEmpty
        ? _text(details['intensity'])
        : event.intensity.isNotEmpty
        ? event.intensity
        : _descriptionField(description, <String>['Intensywność:']);
    final intensity = switch (rawIntensity.toLowerCase()) {
      'low' || 'niska' => 'low',
      'high' || 'wysoka' => 'high',
      _ => 'medium',
    };

    final savedRating = _positiveNumber(details['rating']);
    final legacyRating = RegExp(r'\d+').firstMatch(
      _descriptionField(description, <String>['Planowana ocena:', 'Ocena:']),
    );
    final rating =
        (savedRating ??
                (legacyRating != null
                    ? int.tryParse(legacyRating.group(0)!)
                    : null) ??
                0)
            .clamp(0, 5)
            .toInt();

    String savedText(String key, List<String> labels) {
      final value = _text(details[key]);
      return value.isNotEmpty ? value : _descriptionField(description, labels);
    }

    return PlannedTrainingDefaults(
      date: first10(event.date),
      durationMin:
          savedDuration ??
          (event.durationMin > 0 ? event.durationMin : legacyDuration),
      focuses: focuses,
      intensity: intensity,
      rating: rating,
      wentWell: savedText('went_well', <String>['Co było dobrze:']),
      toImprove: savedText('to_improve', <String>[
        'Do poprawy:',
        'Co trzeba poprawić:',
      ]),
      notes: savedText('notes', <String>['Notatka:', 'Notatki:']),
    );
  }
}
