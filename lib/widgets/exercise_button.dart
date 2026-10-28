import 'package:flutter/material.dart';
import '../theme.dart';

/// Wspólny wygląd akcji prowadzącej do szczegółów ćwiczenia.
class ExerciseButton extends StatelessWidget {
  const ExerciseButton({super.key, required this.onTap, this.label = 'Zobacz ćwiczenie'});
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Align(alignment: Alignment.centerLeft, child: Material(color: c.brandPrimary,
      borderRadius: BorderRadius.circular(Rad.pill), child: InkWell(onTap: onTap,
        borderRadius: BorderRadius.circular(Rad.pill), child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.menu_book_outlined, size: 14, color: c.onBrandPrimary),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: manrope(size: 10, weight: FontWeight.w800,
              letterSpacing: 0, color: c.onBrandPrimary))),
          ])))));
  }
}
