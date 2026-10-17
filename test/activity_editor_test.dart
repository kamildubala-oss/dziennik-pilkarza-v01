import 'package:dziennik_pilkarza/models.dart';
import 'package:dziennik_pilkarza/screens/add_event_screen.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EventItem scheduledEvent({required String type}) => EventItem(
  id: 'plan-1',
  date: '2026-10-13',
  time: '17:30',
  type: type,
  title: type == 'match' ? 'Mecz z Wisłą' : 'Trening: Prowadzenie',
  description: 'Ćwiczenia',
  done: false,
  createdAt: '2026-10-10',
  planned: true,
  focus: 'Prowadzenie',
  durationMin: 45,
  intensity: 'medium',
);

Widget testApp(Widget child) => MaterialApp(
  theme: buildTheme(AppColors.dark, Brightness.dark),
  home: child,
);

void main() {
  testWidgets('edytowanie zaplanowanego treningu otwiera pelny formularz treningu', (tester) async {
    await tester.pumpWidget(testApp(AddEventScreen(editing: scheduledEvent(type: 'training'))));
    expect(find.text('Edytuj trening'), findsOneWidget);
    expect(find.text('Edytuj wydarzenie'), findsNothing);
    expect(find.text('Nad czym pracowałeś? (możesz wybrać kilka)'), findsOneWidget);
  });

  testWidgets('edytowanie zaplanowanego meczu otwiera formularz meczu', (tester) async {
    await tester.pumpWidget(testApp(AddEventScreen(editing: scheduledEvent(type: 'match'))));
    expect(find.text('Edytuj mecz'), findsOneWidget);
    expect(find.text('Edytuj wydarzenie'), findsNothing);
    expect(find.text('Przeciwnik'), findsOneWidget);
  });

  testWidgets('wybrana data z dziennika trafia do formularza nowego treningu', (tester) async {
    await tester.pumpWidget(testApp(const AddEventScreen(
      initialDate: '2026-10-13',
      initialType: 'training',
      isPlanned: false,
    )));
    final field = tester.widget<DateField>(find.byType(DateField));
    expect(field.controller.text, '2026-10-13');
    expect(find.text('Zapisz trening'), findsAtLeastNWidgets(1));
  });
}
