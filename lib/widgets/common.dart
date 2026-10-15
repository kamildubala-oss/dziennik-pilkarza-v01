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
        size: 11,
        weight: FontWeight.w800,
        letterSpacing: 1.5,
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.surfaceSecondary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.close, size: 22, color: c.onSurface),
            ),
          ),
          Text(title, style: barlow(size: 18, color: c.onSurface)),
          const SizedBox(width: 36),
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
              size: 11,
              weight: FontWeight.w800,
              letterSpacing: 1.2,
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
          size: 11,
          weight: FontWeight.w800,
          letterSpacing: 1.2,
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
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool multiline;
  final int minLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final IconData? suffixIcon;

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
      keyboardType: multiline ? TextInputType.multiline : keyboardType,
      minLines: multiline ? minLines : 1,
      maxLines: multiline ? null : 1,
      cursorColor: c.brandPrimary,
      style: manrope(size: 15, color: c.onSurface),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.surfaceSecondary,
        hintText: hint,
        hintStyle: manrope(size: 15, color: c.muted),
        suffixIcon: suffixIcon == null
            ? null
            : Icon(suffixIcon, size: 20, color: c.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Sp.md,
          vertical: 10,
        ),
        border: _border(c.border),
        enabledBorder: _border(c.border),
        focusedBorder: _border(c.border),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.brandPrimary : c.surfaceSecondary,
          borderRadius: BorderRadius.circular(Rad.pill),
          border: Border.all(
            color: selected ? c.brandPrimary : c.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: manrope(
            size: 13,
            weight: FontWeight.w600,
            color: selected ? c.onBrandPrimary : c.onSurface,
          ),
        ),
      ),
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
    return Row(
      children: withGap([
        for (var n = 1; n <= 5; n++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(n),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                n <= rating ? Icons.star : Icons.star_outline,
                size: 28,
                color: n <= rating ? c.brandPrimary : c.muted,
              ),
            ),
          ),
      ], width: 4),
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: onTap == null
                ? c.brandPrimary.withValues(alpha: 0.45)
                : c.brandPrimary,
            borderRadius: BorderRadius.circular(Rad.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon ?? Icons.check, size: 20, color: c.onBrandPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: manrope(
                  size: 14,
                  weight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: c.onBrandPrimary,
                ),
              ),
            ],
          ),
        ),
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
    final fg = onTap == null ? c.muted : c.onSurface;
    return Padding(
      padding: EdgeInsets.only(top: marginTop),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: c.surfaceSecondary,
            borderRadius: BorderRadius.circular(Rad.pill),
            border: Border.all(color: c.borderStrong, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: manrope(
                    size: 14,
                    weight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
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
