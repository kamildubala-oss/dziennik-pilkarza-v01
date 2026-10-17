import 'package:flutter/foundation.dart';

/// Wynik rzeczywistego wykonania operacji, niezależny od obecności klucza.
class CoachRuntime {
  CoachRuntime._();
  static final ValueNotifier<String> lastReplySource = ValueNotifier('');
}
