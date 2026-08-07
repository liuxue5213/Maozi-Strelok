import 'package:flutter/material.dart';

import '../models/reticle.dart';

/// Painter that renders any [ReticleSpec] faithfully, scaling MIL/MOA units to
/// pixels, honoring FFP vs SFP magnification scaling, and overlaying a ballistic
/// hold point. This replaces the old hard-coded 3-reticle painter with a
/// general reticle-library renderer (the Strelok "reticle library" feature).
class ReticleLibraryPainter extends CustomPainter {
  final ReticleSpec spec;
  /// Elevation hold in the reticle's native unit (positive = hold UP).
  final double elevUnits;
  /// Windage hold in the reticle's native unit (positive = hold RIGHT).
  final double windUnits;
  /// Current scope magnification (for SFP scaling; FFP ignores this).
  final double magnification;
  final Color holdColor;

  ReticleLibraryPainter({
    required this.spec,
    required this.elevUnits,
    required this.windUnits,
    this.magnification = 1,
    this.holdColor = Colors.red,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Pixels per reticle unit. The whole field (±fieldHalf) maps to half the
    // canvas, so 1 unit = (size/2) / fieldHalf px at reference magnification.
    final refPxPerUnit = (size.width / 2) / spec.fieldHalf;
    // SFP reticles scale inversely with magnification: at higher zoom each mil
    // subtends more of the FOV, so the reticle appears to cover fewer mils ->
    // effective px/unit shrinks. FFP: constant.
    final sfpScale = spec.focalPlane == 'SFP'
        ? (spec.sfpRefMag / (magnification <= 0 ? 1 : magnification))
        : 1.0;
    final pxPerUnit = refPxPerUnit * sfpScale;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black87;

    // ---- Lines ----
    for (final l in spec.lines) {
      linePaint
        ..strokeWidth = l.width
        ..color = Colors.black87;
      if (l.dashed) {
        _dashed(canvas, Offset(cx + l.x1 * pxPerUnit, cy + l.y1 * pxPerUnit),
            Offset(cx + l.x2 * pxPerUnit, cy + l.y2 * pxPerUnit), linePaint);
      } else {
        canvas.drawLine(
            Offset(cx + l.x1 * pxPerUnit, cy + l.y1 * pxPerUnit),
            Offset(cx + l.x2 * pxPerUnit, cy + l.y2 * pxPerUnit),
            linePaint);
      }
    }

    // ---- Posts (thick stadia) ----
    for (final p in spec.posts) {
      linePaint
        ..strokeWidth = p.width
        ..color = Colors.black87;
      canvas.drawLine(
          Offset(cx + p.x1 * pxPerUnit, cy + p.y1 * pxPerUnit),
          Offset(cx + p.x2 * pxPerUnit, cy + p.y2 * pxPerUnit),
          linePaint);
    }

    // ---- Ticks ----
    for (final t in spec.ticks) {
      linePaint.strokeWidth = t.width;
      if (t.axis == 'v') {
        // tick on the vertical line, extends horizontally
        final y = cy + t.pos * pxPerUnit;
        canvas.drawLine(Offset(cx - t.halfLen * pxPerUnit, y),
            Offset(cx + t.halfLen * pxPerUnit, y), linePaint);
      } else {
        // tick on the horizontal line, extends vertically
        final x = cx + t.pos * pxPerUnit;
        canvas.drawLine(Offset(x, cy - t.halfLen * pxPerUnit),
            Offset(x, cy + t.halfLen * pxPerUnit), linePaint);
      }
    }

    // ---- Dots ----
    final dotPaint = Paint()..color = Colors.black87;
    for (final d in spec.dots) {
      canvas.drawCircle(
          Offset(cx + d.x * pxPerUnit, cy + d.y * pxPerUnit),
          (d.r * pxPerUnit).clamp(1.5, 5.0),
          dotPaint);
    }

    // ---- Circles ----
    for (final c in spec.circles) {
      linePaint.strokeWidth = c.width;
      canvas.drawCircle(
          Offset(cx + c.x * pxPerUnit, cy + c.y * pxPerUnit),
          c.r * pxPerUnit,
          linePaint);
    }

    // ---- Center point ----
    dotPaint..color = Colors.black87;
    canvas.drawCircle(Offset(cx, cy), 1.5, dotPaint);

    // ---- Ballistic hold overlay ----
    // elevUnits positive = bullet low = hold UP = marker drawn DOWN on screen.
    final holdX = cx + windUnits * pxPerUnit;
    final holdY = cy + elevUnits * pxPerUnit;
    final holdPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = holdColor;
    canvas.drawLine(Offset(holdX - 10, holdY), Offset(holdX + 10, holdY), holdPaint);
    canvas.drawLine(Offset(holdX, holdY - 10), Offset(holdX, holdY + 10), holdPaint);
    canvas.drawCircle(Offset(holdX, holdY), 4, holdPaint);
    // dashed lead line center -> hold
    _dashed(canvas, Offset(cx, cy), Offset(holdX, holdY),
        Paint()..style = PaintingStyle.stroke..color = holdColor..strokeWidth = 1);

    // numeric annotation
    final eTxt = '${elevUnits >= 0 ? '↑' : '↓'}${elevUnits.abs().toStringAsFixed(1)}';
    final wTxt = '${windUnits >= 0 ? '→' : '←'}${windUnits.abs().toStringAsFixed(1)}';
    _label(canvas, '$eTxt  $wTxt ${spec.unit}', Offset(holdX + 10, holdY - 6),
        color: holdColor);

    // unit label top-left
    _label(canvas, '${spec.unit} · ${spec.focalPlane}', const Offset(4, 4),
        color: Colors.black54);
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 6.0, gap = 4.0;
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final ux = d.dx / len, uy = d.dy / len;
    double t = 0;
    while (t < len) {
      final e = (t + dash).clamp(0.0, len);
      c.drawLine(Offset(a.dx + ux * t, a.dy + uy * t),
          Offset(a.dx + ux * e, a.dy + uy * e), p);
      t += dash + gap;
    }
  }

  void _label(Canvas c, String text, Offset pos, {Color color = Colors.black87}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, pos);
  }

  @override
  bool shouldRepaint(covariant ReticleLibraryPainter old) =>
      old.spec.id != spec.id ||
      old.elevUnits != elevUnits ||
      old.windUnits != windUnits ||
      old.magnification != magnification;
}
