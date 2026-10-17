import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dziennik_pilkarza/screens/log_session_screen.dart';
import 'package:dziennik_pilkarza/screens/log_match_screen.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:dziennik_pilkarza/theme.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildTheme(AppColors.dark, Brightness.dark),
  home: child,
);
void main() {
  testWidgets(
    'plan has future-oriented fields without post-training evaluation',
    (tester) async {
      await tester.pumpWidget(
        app(
          const LogSessionScreen(isPlanned: true, initialFocuses: ['Strzał']),
        ),
      );
      expect(find.text('Nad czym chcesz pracować?'), findsOneWidget);
      expect(find.byType(RatingStars), findsNothing);
      expect(find.text('Co było dobrze?'), findsNothing);
      expect(find.text('Zapisz plan'), findsOneWidget);
    },
  );
  testWidgets('match plan hides score, goals, assists and self-rating', (
    tester,
  ) async {
    await tester.pumpWidget(app(const LogMatchScreen(isPlanned: true)));
    expect(find.text('Wynik'), findsNothing);
    expect(find.text('Gole'), findsNothing);
    expect(find.text('Asysty'), findsNothing);
    expect(find.byType(RatingStars), findsNothing);
    expect(find.text('Zapisz plan'), findsOneWidget);
  });
  testWidgets(
    'new completed training starts unrated and save remains reachable with keyboard',
    (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        app(const LogSessionScreen(initialFocuses: ['Strzał'])),
      );
      expect(tester.widget<RatingStars>(find.byType(RatingStars)).rating, 0);
      final button = find.byType(PrimaryButton);
      expect(
        tester.getBottomRight(button).dy,
        lessThanOrEqualTo(
          (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
              tester.view.devicePixelRatio,
        ),
      );
      expect(tester.widget<PrimaryButton>(button).onTap, isNotNull);
    },
  );
  testWidgets(
    'closing a changed form offers discard and can return to entered values',
    (tester) async {
      await tester.pumpWidget(
        app(const LogSessionScreen(initialFocuses: ['Strzał'])),
      );
      await tester.enterText(find.byType(TextField).at(1), '75');
      await tester.tap(find.byTooltip('Zamknij formularz'));
      await tester.pumpAndSettle();
      expect(find.text('Odrzucić zmiany?'), findsOneWidget);
      await tester.tap(find.text('Wróć do formularza'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppTextField>(find.byType(AppTextField).at(1))
            .controller
            .text,
        '75',
      );
    },
  );
  testWidgets('large text and narrow viewport keep plan form usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppColors.light, Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const LogSessionScreen(
          isPlanned: true,
          initialFocuses: ['Strzał'],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(PrimaryButton)).height,
      greaterThanOrEqualTo(48),
    );
  });
}
