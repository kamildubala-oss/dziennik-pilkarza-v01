import 'package:flutter/material.dart';
import '../theme.dart';

const jerseyPalette = <({String name, int value})>[
  (name: 'Biały', value: 0xFFFFFFFF), (name: 'Granatowy', value: 0xFF172554),
  (name: 'Niebieski', value: 0xFF2563EB), (name: 'Błękitny', value: 0xFF93C5FD),
  (name: 'Czerwony', value: 0xFFDC2626), (name: 'Bordowy', value: 0xFF881337),
  (name: 'Żółty', value: 0xFFFACC15), (name: 'Pomarańczowy', value: 0xFFF97316),
  (name: 'Zielony', value: 0xFF15803D), (name: 'Limonkowy', value: 0xFFD4FF26),
  (name: 'Fioletowy', value: 0xFF7C3AED), (name: 'Czarny', value: 0xFF171717),
];

class PlayerJersey extends StatelessWidget {
  const PlayerJersey({super.key, this.number, required this.color,
    required this.numberColor, this.size = 44});
  final int? number;
  final Color color;
  final Color numberColor;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: number == null ? 'Koszulka zawodnika bez numeru' : 'Koszulka zawodnika, numer $number',
    child: SizedBox(width: size, height: size,
      child: CustomPaint(painter: _JerseyPainter(color),
        child: Align(alignment: const Alignment(0, 0.22),
          child: Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.24),
            child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(number?.toString() ?? '–',
                style: barlow(size: size * 0.4, color: numberColor))))))));
}

class _JerseyPainter extends CustomPainter {
  const _JerseyPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final shape = Path()..moveTo(.34, .08)..lineTo(.15, .18)..lineTo(.02, .43)
      ..lineTo(.21, .53)..lineTo(.27, .43)..lineTo(.27, .94)..lineTo(.73, .94)
      ..lineTo(.73, .43)..lineTo(.79, .53)..lineTo(.98, .43)..lineTo(.85, .18)
      ..lineTo(.66, .08)..quadraticBezierTo(.5, .24, .34, .08)..close();
    canvas.drawPath(shape, Paint()..color = color);
    canvas.drawPath(shape, Paint()..color = const Color(0x66808080)
      ..style = PaintingStyle.stroke..strokeWidth = .018);
    canvas.drawPath(Path()..moveTo(.35, .09)..quadraticBezierTo(.5, .29, .65, .09),
      Paint()..color = const Color(0x55000000)..style = PaintingStyle.stroke..strokeWidth = .035);
    canvas.restore();
  }
  @override
  bool shouldRepaint(_JerseyPainter oldDelegate) => oldDelegate.color != color;
}
