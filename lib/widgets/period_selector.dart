import 'package:flutter/material.dart';
import '../theme.dart';

/// Cztery okresy zawsze w jednym rzędzie, z pełnymi etykietami i polem 44 px.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const options = {7: '7 dni', 30: '30 dni', -1: 'Sezon', 0: 'Cała historia'};
    return Row(key: const ValueKey('period-selector'), children: [
      for (final entry in options.entries) Expanded(flex: entry.key == 0 ? 5 : 3,
        child: Padding(padding: EdgeInsets.only(right: entry.key == 0 ? 0 : 4),
          child: Semantics(selected: value == entry.key, button: true, label: entry.value,
            child: Material(color: value == entry.key ? c.brandPrimary : c.surfaceSecondary,
              borderRadius: BorderRadius.circular(Rad.pill),
              child: InkWell(key: ValueKey('period-${entry.key}'),
                borderRadius: BorderRadius.circular(Rad.pill),
                onTap: onChanged == null ? null : () => onChanged!(entry.key),
                child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(entry.value,
                    maxLines: 1, softWrap: false,
                    style: manrope(size: 11, weight: FontWeight.w700,
                      color: value == entry.key ? c.onBrandPrimary : c.onSurface))))))))),
    ]);
  }
}
