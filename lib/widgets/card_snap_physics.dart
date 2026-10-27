import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Stops a horizontal workout rail at the beginning of a complete card.
class CardSnapPhysics extends ScrollPhysics {
  const CardSnapPhysics({required this.itemExtent, super.parent});
  final double itemExtent;

  @override
  CardSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      CardSnapPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var page = position.pixels / itemExtent;
    if (velocity < -tolerance.velocity) page -= .5;
    if (velocity > tolerance.velocity) page += .5;
    final target = (page.round() * itemExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity,
      tolerance: tolerance);
  }
}
