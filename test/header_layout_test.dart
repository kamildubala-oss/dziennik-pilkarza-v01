import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dziennik_pilkarza/local_db.dart';
import 'package:dziennik_pilkarza/screens/coach_screen.dart';
import 'package:dziennik_pilkarza/screens/diary_screen.dart';
import 'package:dziennik_pilkarza/services/coach_runtime.dart';
import 'package:dziennik_pilkarza/theme.dart';
import 'package:dziennik_pilkarza/widgets/player_jersey.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb.setDoc('profile', {'name': 'Adam', 'jersey_number': 21});
    CoachRuntime.reset();
  });

  testWidgets('number sits on the chest in home and profile jersey sizes', (tester) async {
    for (final size in [44.0, 64.0]) {
    for (final number in [7, 21, 99]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: PlayerJersey(size: size, number: number, color: Colors.green, numberColor: Colors.white)))));
      final shirt = tester.getRect(find.byType(PlayerJersey));
      final text = tester.getRect(find.text('$number'));
      expect(text.center.dx, closeTo(shirt.center.dx, .5));
      expect(text.center.dy, closeTo(shirt.top + shirt.height * .43, .5));
      expect(text.left, greaterThanOrEqualTo(shirt.left + shirt.width * .27));
      expect(text.right, lessThanOrEqualTo(shirt.left + shirt.width * .73));
    }
    }
  });

  testWidgets('name, shirt and profile button share one center line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.dark, Brightness.dark),
      home: Scaffold(body: DiaryScreen(selected: selected, index: 0, onOpenCoach: () {}))));
    await tester.pumpAndSettle();
    final shirt = tester.getRect(find.byType(PlayerJersey));
    final name = tester.getRect(find.text('Adam'));
    final profile = tester.getRect(find.text('A'));
    expect(name.center.dy, closeTo(shirt.center.dy, .5));
    expect(profile.center.dy, closeTo(shirt.center.dy, .5));
    expect(name.left, greaterThan(shirt.right));
    expect(name.right, lessThan(profile.left));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });

  testWidgets('coach card ends fifteen pixels below subtitle at both text scales', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = ValueNotifier(2);
    for (final scale in [1.0, 1.4]) {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(AppColors.light, Brightness.light),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(body: CoachScreen(selected: selected, index: 2))));
      // The hero layout does not depend on asynchronous workout loading.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final subtitle = find.text('Indywidualny trening · Rozwój umiejętności');
      final card = find.ancestor(of: subtitle, matching: find.byType(ClipRRect)).first;
      expect(tester.getRect(card).bottom - tester.getRect(subtitle).bottom, closeTo(15, .5));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });
}
