import 'package:dziennik_pilkarza/api.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/screens/log_match_screen.dart';
import 'package:dziennik_pilkarza/services/user_errors.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/utils.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget testApp(Widget child) => MaterialApp(
  theme: buildTheme(AppColors.dark, Brightness.dark),
  home: child,
);

void main() {
  test('polskie komunikaty zamiast kodu HTTP', () {
    final message = friendlyError(ApiException(
      422, 'Unprocessable Entity', 'duration_min must be between 0 and 600'));
    expect(message, 'Czas treningu musi wynosić od 0 do 600 minut.');
    expect(message, isNot(contains('422')));
    expect(friendlyError(ApiException(
        409, 'Conflict', 'Completed activity cannot be edited as a plan')),
        contains('już zapisana'));
  });

  test('walidacja nie zamienia tekstu w niejawne zero', () {
    expect(numberFieldError('45 minut', 'Czas (min)', 0, 600), isNotNull);
    expect(numberFieldError('700', 'Czas (min)', 0, 600), isNotNull);
    expect(numberFieldError('-2', 'Czas (min)', 0, 600), isNotNull);
    expect(numberFieldError('45', 'Czas (min)', 0, 600), isNull);
    expect(numberFieldError('0', 'Gole', 0, 20), isNull);
  });

  testWidgets('formularz treningu: 45 minut -> walidacja pod polem', (tester) async {
    await tester.pumpWidget(testApp(LogSessionScreen(
      initialDate: todayIso(), initialFocuses: const <String>['Strzał'],
    )));
    await tester.enterText(find.byType(TextField).at(1), '45 minut');
    await tester.pump();
    expect(find.text('W polu „Czas (min)” wpisz tylko liczbę.'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onTap, isNull);

    await tester.enterText(find.byType(TextField).at(1), '700');
    await tester.pump();
    expect(find.text('W polu „Czas (min)” wpisz liczbę od 0 do 600.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.pump();
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onTap, isNotNull);
  });

  testWidgets('formularz meczu: za duża liczba minut i goli blokuje zapis', (tester) async {
    await tester.pumpWidget(testApp(LogMatchScreen(initialDate: todayIso())));
    // Kolejność: data, rywal, wynik, minuty, gole, asysty.
    await tester.enterText(find.byType(TextField).at(3), '181');
    await tester.pump();
    expect(find.text('W polu „Minuty” wpisz liczbę od 0 do 180.'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onTap, isNull);

    await tester.enterText(find.byType(TextField).at(3), '60');
    await tester.enterText(find.byType(TextField).at(4), '21');
    await tester.pump();
    expect(find.text('W polu „Gole” wpisz liczbę od 0 do 20.'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onTap, isNull);
  });
}
