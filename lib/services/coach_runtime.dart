import 'package:flutter/foundation.dart';

/// Potwierdzone źródło konkretnego wyniku, a nie dostępność internetu/klucza.
class CoachExecution {
  const CoachExecution(this.source, this.operation, this.createdAt);
  final String source;
  final String operation;
  final String createdAt;
}

class CoachRuntime {
  static final last = ValueNotifier<CoachExecution?>(null);
  static void record(String source, String operation, String createdAt) {
    last.value = CoachExecution(source, operation, createdAt);
  }
  static void reset() => last.value = null;
  static String sourceLabel(String source) => switch (source) {
    'online' => 'Online · Gemini',
    'offline' => 'Offline · trener lokalny',
    _ => 'Źródło nie zostało zapisane',
  };
  static String dateLabel(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return 'data nie została zapisana';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
}
