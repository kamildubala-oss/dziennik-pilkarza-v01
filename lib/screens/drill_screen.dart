import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'log_session_screen.dart';

/// Modal ze szczegółami gotowego treningu (ćwiczenia autorskie).
class DrillScreen extends StatelessWidget {
  const DrillScreen({super.key, required this.drill});

  final Drill drill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          ModalHeader(
            title: 'Trening',
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    drill.source,
                    style: manrope(
                      size: 11,
                      weight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: c.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    drill.title,
                    style: barlow(size: 28, color: c.onSurface),
                  ),
                  const SizedBox(height: Sp.md),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pill(
                        c,
                        Icons.timer_outlined,
                        '${drill.durationMin} min',
                      ),
                      _pill(c, Icons.local_fire_department, intensityLabel(drill.intensity)),
                      _pill(c, Icons.gps_fixed, drill.focus),
                    ],
                  ),
                  const SizedBox(height: Sp.lg),
                  Text(
                    drill.description,
                    style: manrope(
                      size: 14,
                      height: 1.43,
                      color: c.onSurfaceSecondary,
                    ),
                  ),
                  const SizedBox(height: Sp.xl),
                  const SectionTitle('KROKI'),
                  const SizedBox(height: Sp.sm),
                  for (var i = 0; i < drill.steps.length; i++)
                    _step(c, i + 1, drill.steps[i]),
                  PrimaryButton(
                    label: 'Zapisz trening',
                    marginTop: Sp.xl,
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        modalRoute<bool>(
                          LogSessionScreen(
                            initialFocuses: <String>[drill.focus],
                            initialDuration: drill.durationMin,
                            initialIntensity: drill.intensity,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(AppColors c, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.onSurface),
          const SizedBox(width: 4),
          Text(
            text,
            style: manrope(
              size: 12,
              weight: FontWeight.w600,
              color: c.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(AppColors c, int number, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: c.surfaceSecondary,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c.brandPrimary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: manrope(
                size: 13,
                weight: FontWeight.w800,
                color: c.onBrandPrimary,
              ),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              text,
              style: manrope(size: 14, height: 1.43, color: c.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
