import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;
import 'app_state.dart';

/// 瞄准演示 (Aim Demo) — shows, from the shooter's view through the scope,
/// exactly where to hold the crosshair for ANY distance. A target silhouette
/// is drawn at the reticle center; the ballistic hold point (elevation +
/// windage) is overlaid on a MIL/MOA graduated reticle. A toggle switches
/// between "hold on reticle" (keep crosshair on target, use hold point) and
/// "dial & hold on target" (adjust turrets so crosshair = point of aim).
///
/// The view auto-zooms like a real variable scope: when the required hold
/// grows beyond the field of view the reticle zooms out so the hold point
/// always stays visible inside the scope circle (a real fixed-mag scope would
/// simply not show the hold — but the point of this page is teaching where to
/// hold, so the hold is always shown, with an arrow on the rim pointing to it).
class AimDemoPage extends StatefulWidget {
  final AppState state;
  final List<TrajectoryPoint> traj;
  const AimDemoPage({super.key, required this.state, required this.traj});

  @override
  State<AimDemoPage> createState() => _AimDemoPageState();
}

class _AimDemoPageState extends State<AimDemoPage> {
  double _rangeYd = 200;
  /// 0 = hold (use reticle hold point), 1 = dial (turrets zero the drop)
  int _mode = 0;
  bool _showMoa = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final traj = widget.traj;
    final rangeM = U.Units.yardsToM(_rangeYd);
    final pt = traj.isEmpty
        ? null
        : traj.reduce((TrajectoryPoint a, TrajectoryPoint b) =>
            (a.range - rangeM).abs() < (b.range - rangeM).abs() ? a : b);

    // In "hold" mode the bullet's actual drop/windage define where the crosshair
    // must sit relative to the target. In "dial" mode we show the hold point at
    // zero (turrets compensate) and display the required clicks.
    final dropM = pt?.drop ?? 0.0;      // bullet impact relative to LOS
    final windM = pt?.windage ?? 0.0;
    final moa = _showMoa;

    final unit = moa ? 'MOA' : 'MIL';
    final dropUnits = moa
        ? U.Units.radToMoa(dropM / rangeM).abs()
        : U.Units.radToMil(dropM / rangeM).abs();
    final windUnits = moa
        ? U.Units.radToMoa(windM / rangeM).abs()
        : U.Units.radToMil(windM / rangeM).abs();
    // clicks needed if dialing
    final clicks = s.clickMoa > 0 ? (dropUnits / s.clickMoa).round() : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('瞄准演示'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _showMoa = !_showMoa),
            child: Text(moa ? 'MOA' : 'MIL',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // controls
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                const Text('距离: ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    min: 50,
                    max: (s.maxRangeYd).clamp(50.0, 2000.0),
                    divisions:
                        (((s.maxRangeYd).clamp(50.0, 2000.0) - 50) / 10).round(),
                    value: _rangeYd.clamp(50.0, s.maxRangeYd),
                    label: '${_rangeYd.toStringAsFixed(0)}yd',
                    onChanged: (v) => setState(() => _rangeYd = v),
                  ),
                ),
                Text('${_rangeYd.toStringAsFixed(0)}yd',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // mode toggle: hold vs dial
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Hold 分划持留')),
                ButtonSegment(value: 1, label: Text('Dial 旋钮归零')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(builder: (ctx, c) {
              final R = math.min(c.maxWidth, c.maxHeight) / 2;
              // In dial mode the crosshair stays on target (turrets absorb the
              // drop), so no zoom is needed. In hold mode the view auto-zooms
              // like lowering a variable scope's magnification until the hold
              // point fits inside ~78% of the scope radius.
              const basePxPerMil = 40.0;
              final show = _mode == 0;
              final dDrop = show ? dropM : 0.0;
              final dWind = show ? windM : 0.0;
              final maxMil = math.max((dDrop / rangeM).abs(),
                      (dWind / rangeM).abs()) *
                  1000;
              var zoom = 1.0;
              if (maxMil > 0) {
                zoom = ((0.78 * R) / (maxMil * basePxPerMil))
                    .clamp(0.3, 1.5)
                    .toDouble();
              }
              final pxPerMil = basePxPerMil * zoom;
              // drop/wind in reticle angular units -> px
              final dropPx = (dDrop / rangeM) * 1000 * pxPerMil;
              final windPx = (dWind / rangeM) * 1000 * pxPerMil;
              return CustomPaint(
                painter: _AimPainter(
                  dropPx: dropPx,
                  windPx: windPx,
                  showDrop: pt != null && show,
                  pxPerMil: pxPerMil,
                  zoom: zoom,
                  unit: unit,
                  dropUnits: dropUnits,
                  windUnits: windUnits,
                  aimUp: dropM < 0,
                  aimLeft: windM > 0,
                ),
                child: const SizedBox.expand(),
              );
            }),
          ),
          // readout
          if (pt != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    _mode == 0
                        ? '${_rangeYd.toStringAsFixed(0)}yd → 瞄准点应在目标'
                            '${dropM < 0 ? '上方' : '下方'} ${dropUnits.toStringAsFixed(1)} $unit,'
                            '${windM > 0 ? '左' : '右'} ${windUnits.toStringAsFixed(1)} $unit'
                        : '${_rangeYd.toStringAsFixed(0)}yd → 需旋钮补偿 ${dropUnits.toStringAsFixed(1)} $unit'
                            ' (约 $clicks 格)，十字线对准目标中心即可',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '剩余速度 ${_fmtV(pt.speed)} · 飞行时间 ${pt.timeOfFlight.toStringAsFixed(2)}s',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _fmtV(double mps) {
    final sys = widget.state.unitSystem;
    return sys == U.UnitSystem.imperial
        ? '${(mps * 3.28084).toStringAsFixed(0)} fps'
        : '${mps.toStringAsFixed(0)} m/s';
  }
}

/// Paints the scope view: graduated MIL/MOA reticle, target silhouette, and
/// the hold point. The target is always centered; the crosshair is drawn
/// offset by the hold (in hold mode) so the user sees "put the crosshair HERE
/// to hit the target". The view is clipped to the scope circle and auto-zooms
/// so the hold stays visible; when the true hold would be off the reticle, a
/// red arrow on the rim points in its direction.
class _AimPainter extends CustomPainter {
  final double dropPx; // px the crosshair must move UP (+ = aim above target)
  final double windPx;
  final bool showDrop;
  final double pxPerMil;  // px per MIL at current zoom (tick base spacing)
  final double zoom;      // current zoom factor (for target scaling + label)
  final String unit;      // 'MIL' or 'MOA' (tick/readout unit)
  final double dropUnits; // hold magnitude up/down in units
  final double windUnits; // hold magnitude left/right in units
  final bool aimUp;       // drop<0 -> aim above the target
  final bool aimLeft;     // wind>0 -> aim to the left

  _AimPainter({
    required this.dropPx,
    required this.windPx,
    required this.showDrop,
    required this.pxPerMil,
    required this.zoom,
    required this.unit,
    required this.dropUnits,
    required this.windUnits,
    required this.aimUp,
    required this.aimLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(size.width, size.height) / 2;

    // scope tube background
    canvas.drawCircle(Offset(cx, cy), R, Paint()..color = Colors.black);
    canvas.drawCircle(
        Offset(cx, cy),
        R - 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.grey.shade800
          ..strokeWidth = 4);

    // Clip everything to the scope interior so ticks / lines / hold end at
    // the rim instead of spilling onto the page background.
    final clip = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: R - 4));
    canvas.save();
    canvas.clipPath(clip);

    // Graduated reticle background. Ticks are drawn at a fixed, readable pixel
    // spacing; the angular value per tick adapts to the current zoom.
    final pxPerUnit = unit == 'MOA' ? pxPerMil / 3.4377 : pxPerMil;
    _drawTicks(canvas, size, cx, cy, R, pxPerUnit);

    // crosshair center lines
    final linePaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), linePaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), linePaint);

    // target: a simple silhouette / bullseye at reticle center
    _drawTarget(canvas, cx, cy, zoom);

    if (showDrop) {
      // The HOLD crosshair: where the shooter must actually place the crosshair.
      // dropPx = (dropM/rangeM)*1000*pxPerMil. drop is NEGATIVE (bullet low)
      // when the bullet falls below the LOS, so the crosshair must sit ABOVE
      // the target: hy = cy + dropPx (dropPx<0 -> hy above center).
      // wind +right -> aim LEFT: hx = cx - windPx.
      final hx = cx - windPx;
      final hy = cy + dropPx;
      final maxR = R - 14;
      final d = Offset(hx - cx, hy - cy);
      final len = d.distance;
      final inView = len <= maxR;
      double px, py;
      if (inView) {
        px = hx;
        py = hy;
      } else if (len > 0) {
        // Clamp the drawn crosshair to the rim; a red arrow still shows the
        // true direction so the user never loses track of the hold.
        final k = maxR / len;
        px = cx + d.dx * k;
        py = cy + d.dy * k;
      } else {
        px = cx;
        py = cy;
      }

      // dashed connection center -> drawn hold position
      final dashPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;
      _dashed(canvas, Offset(cx, cy), Offset(px, py), dashPaint);

      // red hold crosshair
      final holdPaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawLine(
          Offset(px - 18, py), Offset(px + 18, py), holdPaint);
      canvas.drawLine(
          Offset(px, py - 18), Offset(px, py + 18), holdPaint);

      // rim arrow pointing at the (off-screen) true hold position; kept inside
      // the scope circle so the clip never cuts it off
      if (!inView && len > 0) {
        final dir = Offset(d.dx / len, d.dy / len);
        final perp = Offset(-dir.dy, dir.dx);
        final tip = Offset(px, py) - dir * 8; // pointing outward
        final base = tip - dir * 14;
        final p1 = base + perp * 6;
        final p2 = base - perp * 6;
        final arrow = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close();
        canvas.drawPath(arrow, Paint()..color = Colors.redAccent);
      }

      // hold readout badge near the drawn crosshair
      if (dropPx != 0 || windPx != 0) {
        final txt = dropUnits > 0
            ? '${dropUnits.toStringAsFixed(1)}$unit ${aimUp ? '上' : '下'}'
            : '';
        final w = windUnits > 0
            ? '${windUnits.toStringAsFixed(1)}$unit ${aimLeft ? '左' : '右'}'
            : '';
        _badge(canvas, [txt, w].where((s) => s.isNotEmpty).join(' · '),
            Offset(px, py), cx, cy, R);
      }
    }

    canvas.restore();

    // info labels drawn outside the clip
    final tp = TextPainter(
      text: const TextSpan(
          text: 'SCOPE VIEW',
          style: TextStyle(color: Colors.white38, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(10, 10));
    final zm = TextPainter(
      text: TextSpan(
          text: '倍率 ×${zoom.toStringAsFixed(1)}',
          style: const TextStyle(color: Colors.white38, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    zm.paint(canvas, Offset(size.width - zm.width - 10, 10));
  }

  /// Graduated reticle ticks. The angular value per major tick is chosen so
  /// the pixel spacing stays readable at every zoom level (e.g. every 1 MIL
  /// zoomed in, every 2-5 MIL zoomed out); a minor tick splits each interval.
  void _drawTicks(Canvas canvas, Size size, double cx, double cy, double R,
      double pxPerUnit) {
    final valuePerTick = _niceTick(pxPerUnit);
    final spacing = valuePerTick * pxPerUnit;
    if (spacing < 6) return;
    final half = spacing / 2;
    final maxH = (R / half).ceil();
    for (int s = -maxH; s <= maxH; s++) {
      if (s == 0) continue;
      final off = s * half;
      final x = cx + off;
      final y = cy + off;
      final major = s % 2 == 0;
      final p = Paint()
        ..color = major ? Colors.white70 : Colors.white24
        ..strokeWidth = major ? 1.5 : 1.0;
      final len = major ? 15.0 : 6.0;
      canvas.drawLine(Offset(x, cy - len), Offset(x, cy + len), p);
      canvas.drawLine(Offset(cx - len, y), Offset(cx + len, y), p);
      if (major && off.abs() <= R - 20) {
        final val = (s / 2) * valuePerTick;
        final t = TextPainter(
          text: TextSpan(
              text: _fmtTick(val),
              style: const TextStyle(color: Colors.white38, fontSize: 9)),
          textDirection: TextDirection.ltr,
        )..layout();
        t.paint(canvas, Offset(x - t.width / 2, cy + 17));
        t.paint(canvas, Offset(cx + 17, y - t.height / 2));
      }
    }
  }

  String _fmtTick(double v) {
    if ((v - v.roundToDouble()).abs() < 0.05) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  /// Pick the "nice" angular value per major tick so the on-screen spacing
  /// stays between ~22 and ~54 px across the whole zoom range.
  double _niceTick(double pxPerUnit) {
    const nice = [
      0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0,
    ];
    double v = 1.0;
    for (int guard = 0; guard < 200; guard++) {
      final s = v * pxPerUnit;
      if (s < 22) {
        final i = nice.indexWhere((e) => e > v);
        v = i < 0 ? v * 10 : nice[i];
      } else if (s > 54) {
        final i = nice.lastIndexWhere((e) => e < v);
        v = i < 0 ? v / 10 : nice[i];
      } else {
        return v;
      }
    }
    return v;
  }

  void _drawTarget(Canvas canvas, double cx, double cy, double zoom) {
    // bullseye target (IPSC-ish circle), scaled with the scope magnification
    final rings = [
      (r: 42.0, c: Colors.white),
      (r: 34.0, c: Colors.black),
      (r: 26.0, c: Colors.white),
      (r: 16.0, c: Colors.black),
      (r: 8.0, c: Colors.redAccent),
    ];
    for (final ring in rings) {
      canvas.drawCircle(
          Offset(cx, cy), ring.r * zoom, Paint()..color = ring.c);
    }
  }

  /// Small dark readout box anchored at [at], kept inside the scope circle.
  void _badge(Canvas canvas, String text, Offset at, double cx, double cy,
      double R) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    var x = at.dx + 14;
    var y = at.dy - 26;
    final dist = Offset(x - cx, y - cy).distance;
    if (dist > 0 && dist + 30 > R) {
      final k = (R - 30) / dist;
      x = cx + (x - cx) * k;
      y = cy + (y - cy) * k;
    }
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, tp.width + 12, tp.height + 6),
        const Radius.circular(4));
    canvas.drawRRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.7));
    tp.paint(canvas, Offset(x + 6, y + 3));
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

  @override
  bool shouldRepaint(covariant _AimPainter old) =>
      old.dropPx != dropPx ||
      old.windPx != windPx ||
      old.showDrop != showDrop ||
      old.pxPerMil != pxPerMil ||
      old.zoom != zoom ||
      old.unit != unit ||
      old.dropUnits != dropUnits ||
      old.windUnits != windUnits ||
      old.aimUp != aimUp ||
      old.aimLeft != aimLeft;
}
