import 'package:flutter/material.dart';

import '../theme.dart';
import 'calendar_screen.dart';
import 'coach_screen.dart';
import 'diary_screen.dart';
import 'progress_screen.dart';

/// Dolna nawigacja z 4 zakładkami: Dziennik, Kalendarz, Trener, Postęp.
/// Zakładki tworzone są leniwie (przy pierwszym wejściu) i zachowują stan.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _current = 0;
  final Set<int> _visited = <int>{0};
  final ValueNotifier<int> _selected = ValueNotifier<int>(0);

  void _select(int i) {
    setState(() {
      _current = i;
      _visited.add(i);
    });
    _selected.value = i;
  }

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  Widget _page(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return DiaryScreen(
          selected: _selected,
          index: 0,
          onOpenCoach: () => _select(2),
        );
      case 1:
        return CalendarScreen(selected: _selected, index: 1);
      case 2:
        return CoachScreen(selected: _selected, index: 2);
      default:
        return ProgressScreen(selected: _selected, index: 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.surface,
      body: IndexedStack(
        index: _current,
        children: List<Widget>.generate(4, _page),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surfaceSecondary,
          border: Border(top: BorderSide(color: c.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _current,
          onTap: _select,
          type: BottomNavigationBarType.fixed,
          backgroundColor: c.surfaceSecondary,
          selectedItemColor: c.brandPrimary,
          unselectedItemColor: c.muted,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: manrope(size: 11, weight: FontWeight.w600),
          unselectedLabelStyle: manrope(size: 11, weight: FontWeight.w600),
          showUnselectedLabels: true,
          elevation: 0,
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Dziennik',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Kalendarz',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.sports), label: 'Trener'),
            BottomNavigationBarItem(
              icon: Icon(Icons.show_chart),
              label: 'Postęp',
            ),
          ],
        ),
      ),
    );
  }
}
