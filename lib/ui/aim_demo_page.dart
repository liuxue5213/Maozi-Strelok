import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;
import 'app_state.dart';

/// 瞄准演示 (Aim Demo) — shows, from the shooter's view through the scope,
/// exactly where to hold the crosshair for ANY distance. A target silhouette
/// is drawn at the reticle center; the ballistic hold point (elevation +
/// windage) is overlaid. A toggle switches between "hold on reticle" (keep
/// crosshair on target, use hold point) and "dial & hold on target" (adjust
/// turrets so crosshair = point of aim). This is the intuitive "不同距离实际
/// 瞄准哪里" visualization.
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

    // pixels per meter at the target (view scale): target at range is rendered
    // at a fixed angular size, so 1 m at the target = (px_per_mil / 1000)*range
    final pxPerMil = 40.0; // 1 MIL spans 40 px in this view
    // drop/wind in reticle angular units -> px
    final dropPx = (dropM / rangeM) * 1000 * pxPerMil;
    final windPx = (windM / rangeM) * 1000 * pxPerMil;

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
            child: CustomPaint(
              painter: _AimPainter(
                dropPx: _mode == 0 ? dropPx : 0,
                windPx: _mode == 0 ? windPx : 0,
                showDrop: pt != null,
              ),
              child: const SizedBox.expand(),
            ),
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

/// Paints the scope view: crosshair, target silhouette, and the hold point.
/// The target is always centered; the crosshair is drawn offset by the hold
/// (in hold mode) so the user sees "put the crosshair HERE to hit the target".
class _AimPainter extends CustomPainter {
  final double dropPx; // px the crosshair must move UP (+ = aim above target)
  final double windPx;
  final bool showDrop;

  _AimPainter({required this.dropPx, required this.windPx, required this.showDrop});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // scope tube background
    canvas.drawCircle(Offset(cx, cy), size.width / 2, Paint()..color = Colors.black);
    canvas.drawCircle(
        Offset(cx, cy),
        size.width / 2 - 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.grey.shade800
          ..strokeWidth = 4);

    final linePaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.2;
    // crosshair centered at (cx, cy)
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), linePaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), linePaint);

    // target: a simple silhouette / bullseye at reticle center
    _drawTarget(canvas, cx, cy);

    if (showDrop) {
      // The HOLD crosshair: where the shooter must actually place the crosshair.
      // dropPx = (dropM/rangeM)*1000*40. drop is NEGATIVE (bullet low) when the
      // bullet falls below the LOS, so the crosshair must sit ABOVE the target:
      // hy = cy + dropPx (dropPx<0 -> hy above center). wind +right -> aim LEFT:
      // hx = cx - windPx.
      final hx = cx - windPx; // wind +right -> crosshair moves LEFT of target
      final hy = cy + dropPx; // drop negative -> crosshair moves UP (above target)
      final holdPaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawLine(
          Offset(hx - 18, hy), Offset(hx + 18, hy), holdPaint);
      canvas.drawLine(
          Offset(hx, hy - 18), Offset(hx, hy + 18), holdPaint);
      // dashed connection
      final dashPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;
      _dashed(canvas, Offset(cx, cy), Offset(hx, hy), dashPaint);
    }

    // magnifier info
    final tp = TextPainter(
      text: const TextSpan(
          text: 'SCOPE VIEW',
          style: TextStyle(color: Colors.white38, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(8, 8));
  }

  void _drawTarget(Canvas canvas, double cx, double cy) {
    // bullseye target (IPSC-ish circle)
    final rings = [
      (r: 42.0, c: Colors.white),
      (r: 34.0, c: Colors.black),
      (r: 26.0, c: Colors.white),
      (r: 16.0, c: Colors.black),
      (r: 8.0, c: Colors.redAccent),
    ];
    for (final ring in rings) {
      canvas.drawCircle(Offset(cx, cy), ring.r, Paint()..color = ring.c);
    }
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
      old.dropPx != dropPx || old.windPx != windPx || old.showDrop != showDrop;
}
