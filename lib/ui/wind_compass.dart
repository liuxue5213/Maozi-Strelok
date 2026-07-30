import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A tappable wind-direction compass. The shooter is at the center facing
/// toward the top of the dial (downrange / target). An arrow shows the
/// direction the wind blows FROM.
///
/// The compass reports back the selected "wind from" bearing via [onChanged],
/// where 0° = wind from downrange (headwind), clockwise.
class WindCompass extends StatelessWidget {
  final double windFrom;
  final ValueChanged<double> onChanged;
  final double size;

  const WindCompass({
    super.key,
    required this.windFrom,
    required this.onChanged,
    this.size = 96,
  });

  void _handle(Offset local) {
    final cx = size / 2;
    final cy = size / 2;
    final dx = local.dx - cx;
    final dyUp = cy - local.dy; // up is positive
    var deg = math.atan2(dx, dyUp) * 180 / math.pi;
    if (deg < 0) deg += 360;
    onChanged(deg);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        onPanUpdate: (d) => _handle(d.localPosition),
        onTapDown: (d) => _handle(d.localPosition),
        child: CustomPaint(
          painter: _CompassPainter(windFrom: windFrom),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double windFrom; // degrees, 0 = from downrange (top), CW

  _CompassPainter({required this.windFrom});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Outer ring
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.grey);

    // Cardinal ticks + labels: 0=Top(Target), 90=Right, 180=Bottom(Shooter), 270=Left
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.grey;
    const labels = ['目标', '右', '射手', '左'];
    for (int i = 0; i < 4; i++) {
      final a = i * 90 * math.pi / 180;
      final p1 = Offset(center.dx + radius * math.sin(a),
          center.dy - radius * math.cos(a));
      final p2 = Offset(center.dx + (radius - 8) * math.sin(a),
          center.dy - (radius - 8) * math.cos(a));
      canvas.drawLine(p1, p2, tickPaint);
      final tp = TextPainter(
        text: TextSpan(
            text: labels[i],
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(
              center.dx + (radius - 20) * math.sin(a) - tp.width / 2,
              center.dy - (radius - 20) * math.cos(a) - tp.height / 2));
    }

    // Wind arrow: from the windFrom direction pointing toward center.
    final a = windFrom * math.pi / 180;
    final origin = Offset(center.dx + radius * 0.85 * math.sin(a),
        center.dy - radius * 0.85 * math.cos(a));
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.blue;
    canvas.drawLine(origin, center, arrow);
    // arrowhead at center
    const headLen = 7.0;
    const headAngle = 0.5;
    final dir = (center - origin);
    final dlen = dir.distance;
    if (dlen > 0) {
      final ux = dir.dx / dlen;
      final uy = dir.dy / dlen;
      final tip = center;
      for (final sgn in [1.0, -1.0]) {
        final hx = tip.dx -
            ux * headLen +
            sgn * (-uy) * headLen * math.tan(headAngle);
        final hy = tip.dy -
            uy * headLen -
            sgn * (ux) * headLen * math.tan(headAngle);
        canvas.drawLine(tip, Offset(hx, hy), arrow);
      }
    }

    // Center dot (shooter)
    canvas.drawCircle(center, 4, Paint()..color = Colors.black87);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      old.windFrom != windFrom;
}
