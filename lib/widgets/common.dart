import 'package:flutter/material.dart';

import '../theme.dart';

/// Wstawia odstęp między elementami (odpowiednik `gap` z React Native).
List<Widget> withGap(List<Widget> items, {double? width, double? height}) {
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) out.add(SizedBox(width: width, height: height));
    out.add(items[i]);
  }
  return out;
}

/// Ekran modalny wjeżdżający od dołu (jak `presentation: "modal"`).
Route<T> modalRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

Future<T?> pushModal<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(modalRoute<T>(page));
}

/// Mały spinner (odpowiednik `ActivityIndicator`).
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.color, this.size = 20});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color ?? context.c.brandPrimary,
      ),
    );
  }
}

/// Mały nagłówek sekcji, np. "OSTATNIE WPISY".
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: manrope(
        size: 13,
        weight: FontWeight.w800,
        letterSpacing: 0.6,
        color: context.c.muted,
      ),
    );
  }
}

/// Nagłówek ekranu modalnego: [X]  Tytuł  [ ].
class ModalHeader extends StatelessWidget {
  const ModalHeader({super.key, required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(Sp.lg, top + Sp.sm, Sp.lg, Sp.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton.filledTonal(
            tooltip: 'Zamknij formularz',
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: barlow(size: 20, color: c.onSurface),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// Pole z etykietą nad zawartością.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: manrope(
              size: 13,
              weight: FontWeight.w800,
              letterSpacing: 0.4,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Etykieta pola bez dolnego marginesu (ekran "Nowe wydarzenie").
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: manrope(
          size: 13,
          weight: FontWeight.w800,
          letterSpacing: 0.4,
          color: context.c.muted,
        ),
      ),
    );
  }
}

/// Pole tekstowe w stylu aplikacji.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.multiline = false,
    this.minLines = 3,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool multiline;
  final int minLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final IconData? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Rad.md),
    borderSide: BorderSide(color: color, width: 1),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      keyboardType: multiline ? TextInputType.multiline : keyboardType,
      minLines: multiline ? minLines : 1,
      maxLines: multiline ? null : 1,
      cursorColor: c.brandPrimary,
      style: manrope(size: 15, color: c.onSurface),
      decoration: InputDecoration(
        constraints: const BoxConstraints(minHeight: 48),
        isDense: true,
        filled: true,
        fillColor: c.surfaceSecondary,
        hintText: hint,
        hintStyle: manrope(size: 15, color: c.muted),
        errorText: errorText,
        suffixIcon: suffixIcon == null
            ? null
            : Icon(suffixIcon, size: 20, color: c.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Sp.md,
          vertical: 10,
        ),
        border: _border(c.border),
        enabledBorder: _border(c.border),
        focusedBorder: _border(c.brandPrimary),
      ),
    );
  }
}

/// Pole daty (RRRR-MM-DD) - po dotknięciu otwiera kalendarz wyboru daty.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.controller});

  final TextEditingController controller;

  Future<void> _pick(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final current = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('pl'),
      helpText: 'Wybierz datę',
      cancelText: 'Anuluj',
      confirmText: 'OK',
    );
    if (picked != null) {
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      controller.text = '${picked.year}-$m-$d';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      readOnly: true,
      onTap: () => _pick(context),
      suffixIcon: Icons.calendar_month_outlined,
    );
  }
}

/// Wybieralna "pigułka" (chip).
class ChipOption extends StatelessWidget {
  const ChipOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: true,
      selectedColor: c.brandTertiary,
      labelStyle: manrope(
        size: 14,
        color: selected ? c.onBrandTertiary : c.onSurface,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }
}

/// Rząd chipów z odstępami 6.
class ChipsWrap extends StatelessWidget {
  const ChipsWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: children);
  }
}

/// Gwiazdki oceny 1-5.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            for (var n = 1; n <= 5; n++)
              Semantics(
                selected: n == rating,
                child: IconButton(
                  tooltip: 'Ocena $n z 5',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => onChanged(n),
                  icon: Icon(
                    n <= rating ? Icons.star : Icons.star_outline,
                    size: 28,
                    color: n <= rating ? c.brandPrimary : c.muted,
                  ),
                ),
              ),
          ],
        ),
        Text(
          rating == 0
              ? 'Opcjonalnie · 1 = trudno, 5 = bardzo dobrze'
              : '$rating/5 · Twoja samoocena',
          style: manrope(size: 13, color: c.muted),
        ),
        if (rating > 0)
          TextButton(
            onPressed: () => onChanged(0),
            child: const Text('Pomiń ocenę'),
          ),
      ],
    );
  }
}

/// Główny przycisk akcji (zielony, zaokrąglony).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.marginTop = Sp.sm,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double marginTop;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(top: marginTop),
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          backgroundColor: c.brandPrimary,
          foregroundColor: c.onBrandPrimary,
          textStyle: manrope(size: 15, weight: FontWeight.w700),
        ),
        icon: Icon(icon ?? Icons.check, size: 20),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Przycisk drugorzędny (obramowany).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.marginTop = Sp.sm,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double marginTop;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(top: marginTop),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          foregroundColor: c.onSurface,
          side: BorderSide(color: c.borderStrong),
          textStyle: manrope(size: 15, weight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

/// Pole godziny (HH:MM) - po dotknięciu otwiera zegar wyboru godziny.
class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.controller, this.hint});

  final TextEditingController controller;
  final String? hint;

  Future<void> _pick(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final parts = controller.text.trim().split(':');
    final initial = parts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 17,
            minute: int.tryParse(parts[1]) ?? 0,
          )
        : const TimeOfDay(hour: 17, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Wybierz godzinę',
      cancelText: 'Anuluj',
      confirmText: 'OK',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      controller.text = '$h:$m';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      hint: hint,
      readOnly: true,
      onTap: () => _pick(context),
      suffixIcon: Icons.schedule,
    );
  }
}

/// Wspólna reakcja na dotyk dla kart, z etykietą i stanem przycisku.
class AppTapTarget extends StatefulWidget {
  const AppTapTarget({
    super.key,
    this.behavior,
    required this.onTap,
    required this.child,
  });
  final HitTestBehavior? behavior;
  final VoidCallback? onTap;
  final Widget child;
  @override
  State<AppTapTarget> createState() => _AppTapTargetState();
}

class _AppTapTargetState extends State<AppTapTarget> {
  bool _pressed = false;
  void _press(bool value) {
    if (mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onTap != null,
    child: GestureDetector(
      behavior: widget.behavior ?? HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.7 : 1,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    ),
  );
}
