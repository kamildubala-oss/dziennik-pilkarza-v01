import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/offline_coach.dart';
import 'package:dziennik_pilkarza/screens/drill_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all library exercises have individual descriptions and distinct recipes', () async {
    final library = await OfflineCoach.exercises();
    expect(library, hasLength(72));
    final recipes = <String>{};
    for (final exercise in library) {
      final description = exercise['description'] as String;
      final steps = (exercise['steps'] as List).cast<String>();
      expect(description.length, greaterThan(35), reason: exercise['id'].toString());
      expect(steps.length, greaterThanOrEqualTo(4));
      expect(steps.toSet().length, steps.length);
      expect(steps, isNot(contains(description)));
      expect(recipes.add(steps.join('|')), isTrue, reason: exercise['id'].toString());
      for (final generic in ['Wykonuj krótkie serie z przerwą',
        'Praca spokojna, przerwy według potrzeby', 'Przećwicz zadanie:', 'Obserwuj:']) {
        expect(steps.join(' '), isNot(contains(generic)));
      }
      expect(exercise['participants_max'], lessThanOrEqualTo(2));
    }
  });

  testWidgets('direction change card gives a turn recipe without metadata paragraphs', (tester) async {
    final exercise = (await Api.drills()).singleWhere((d) => d.id == 'v23_ex006');
    expect(exercise.description, contains('180°'));
    expect(exercise.steps.join(' '), contains('4 m'));
    expect(exercise.steps.join(' '), contains('Wewnętrzną częścią prawej stopy'));
    expect(exercise.steps.join(' '), contains('lewą nogą'));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
      home: DrillScreen(drill: exercise)));
    await tester.pumpAndSettle();
    expect(find.text(exercise.description), findsOneWidget);
    for (final label in ['Cel:', 'Sprzęt:', 'Przestrzeń:', 'Uczestnicy:', 'Wiek:']) {
      expect(find.textContaining(label), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
