import 'package:flutter/material.dart';

import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;
import 'app_state.dart';

/// Reticle simulation page. Draws a generic reticle (choice of crosshair /
/// MIL-dot / MOA grid) and overlays the elevation + windage hold points for a
/// user-selected target range, computed from the solved trajectory.
///
/// This mirrors the headline feature of Strelok: "see holdovers on the reticle
/// without turning knobs".
class ReticlePage extends StatefulWidget {
  final AppState state;
  final List<TrajectoryPoint> traj;
  const ReticlePage({super.key, required this.state, required this.traj});

  @override
  State<ReticlePage> createState() => _ReticlePageState();
}

enum ReticleType { crosshair, milDot, moaGrid }

class _ReticlePageState extends State<ReticlePage> {
  ReticleType _reticle = ReticleType.milDot;
  double _targetYd = 500;
  bool _showMoa = false; // false => MIL

  @override
  Widget build(BuildContext context) {
    final traj = widget.traj;
    final sys = widget.state.unitSystem;
    // find the trajectory point nearest the chosen target range
    final targetM = U.Units.yardsToM(_targetYd);
    final pt = traj.isEmpty
        ? null
        : traj.reduce((a, b) =>
            (a.range - targetM).abs() < (b.range - targetM).abs() ? a : b);

    // hold-off angles (radians) -> reticle units
    double elevRad = 0, windRad = 0;
    if (pt != null && pt.range > 1) {
      elevRad = pt.comeUpRad; // positive = aim higher (bullet low)
      windRad = pt.windage / pt.range; // +right
    }
    final elevUnits = _showMoa
        ? U.Units.radToMoa(elevRad)
        : U.Units.radToMil(elevRad);
    final windUnits = _showMoa
        ? U.Units.radToMoa(windRad)
        : U.Units.radToMil(windRad);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分划板模拟'),
        actions: [
          IconButton(
            tooltip: _showMoa ? '切换 MIL' : '切换 MOA',
            onPressed: () => setState(() => _showMoa = !_showMoa),
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('分划板: '),
                DropdownButton<ReticleType>(
                  value: _reticle,
                  items: const [
                    DropdownMenuItem(
                        value: ReticleType.crosshair, child: Text('十字线')),
                    DropdownMenuItem(
                        value: ReticleType.milDot, child: Text('密位点')),
                    DropdownMenuItem(
                        value: ReticleType.moaGrid, child: Text('MOA 网格')),
                  ],
                  onChanged: (v) => setState(() => _reticle = v ?? ReticleType.milDot),
                ),
                const SizedBox(width: 16),
                const Text('目标距离: '),
                Expanded(
                  child: Slider(
                    min: 25,
                    max: (widget.state.maxRangeYd).clamp(25.0, 2000.0),
                    divisions: (((widget.state.maxRangeYd).clamp(25.0, 2000.0) - 25) / 25).round(),
                    value: _targetYd.clamp(25.0, widget.state.maxRangeYd),
                    label: '${_targetYd.toStringAsFixed(0)} yd',
                    onChanged: (v) => setState(() => _targetYd = v),
                  ),
                ),
                Text('${_targetYd.toStringAsFixed(0)}yd',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CustomPaint(
                    painter: _ReticlePainter(
                      type: _reticle,
                      elevUnits: elevUnits,
                      windUnits: windUnits,
                      unitName: _showMoa ? 'MOA' : 'MIL',
                      unitLabel: _showMoa ? 'MOA' : 'MIL',
                    ),
                  ),
                ),
              ),
            ),
          ),
          // readout card
          if (pt != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                          '目标 ${_targetYd.toStringAsFixed(0)}yd  修正点',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _readout('高低', '${elevUnits.toStringAsFixed(1)} ${_showMoa ? 'MOA' : 'MIL'}',
                              pt.comeUpRad > 0 ? '↑ 抬高' : '↓ 压低'),
                          _readout('风向', '${windUnits.toStringAsFixed(1)} ${_showMoa ? 'MOA' : 'MIL'}',
                              windRad >= 0 ? '→ 向右' : '← 向左'),
                          _readout('剩余速度',
                              Fmt_velocity(pt.speed, sys), ''),
                          _readout('飞行时间', '${pt.timeOfFlight.toStringAsFixed(2)}s', ''),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String Fmt_velocity(double mps, U.UnitSystem sys) =>
      sys == U.UnitSystem.imperial
          ? '${(mps * 3.28084).toStringAsFixed(0)} fps'
          : '${mps.toStringAsFixed(0)} m/s';

  Widget _readout(String label, String value, String hint) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        if (hint.isNotEmpty)
          Text(hint, style: const TextStyle(fontSize: 11, color: Colors.blue)),
      ],
    );
  }
}

/// Paints a reticle with an overlaid hold point.
class _ReticlePainter extends CustomPainter {
  final ReticleType type;
  final double elevUnits; // units to hold UP (positive)
  final double windUnits; // units to hold RIGHT (positive)
  final String unitName;
  final String unitLabel;

  _ReticlePainter({
    required this.type,
    required this.elevUnits,
    required this.windUnits,
    required this.unitName,
    required this.unitLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    // 1 reticle unit = this many pixels. Field of view ~ 20 MIL or 30 MOA.
    final unitPx = type == ReticleType.moaGrid
        ? size.width / 30 // 30 MOA wide
        : size.width / 20; // 20 MIL wide

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black87;
    final dotPaint = Paint()..color = Colors.black87;
    final holdPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red;

    // main crosshair
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), linePaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), linePaint);
    // thick center post
    canvas.drawCircle(Offset(cx, cy), 2, dotPaint);

    // reticle-specific tick marks / dots
    if (type == ReticleType.milDot) {
      for (int i = -8; i <= 8; i++) {
        if (i == 0) continue;
        final off = i * unitPx;
        // vertical dots
        canvas.drawCircle(Offset(cx, cy - off), 2.5, dotPaint);
        canvas.drawCircle(Offset(cx, cy + off), 2.5, dotPaint);
        // horizontal dots
        canvas.drawCircle(Offset(cx + off, cy), 2.5, dotPaint);
        canvas.drawCircle(Offset(cx - off, cy), 2.5, dotPaint);
      }
    } else if (type == ReticleType.moaGrid || type == ReticleType.crosshair) {
      for (int i = -10; i <= 10; i++) {
        if (i == 0) continue;
        final off = i * unitPx;
        // short ticks
        canvas.drawLine(Offset(cx - 4, cy - off), Offset(cx + 4, cy - off),
            linePaint);
        canvas.drawLine(Offset(cx - off, cy - 4), Offset(cx - off, cy + 4),
            linePaint);
      }
    }

    // hold point: screen down = bullet low = aim up (positive elevUnits).
    // On the reticle, holding UP means placing the point BELOW the target on
    // the reticle, so the hold marker is drawn at (cx + wind, cy + elev).
    final holdX = cx + windUnits * unitPx;
    final holdY = cy + elevUnits * unitPx;
    // hold cross
    canvas.drawLine(
        Offset(holdX - 10, holdY), Offset(holdX + 10, holdY), holdPaint);
    canvas.drawLine(
        Offset(holdX, holdY - 10), Offset(holdX, holdY + 10), holdPaint);
    canvas.drawCircle(Offset(holdX, holdY), 4, holdPaint);
    // dashed line from center to hold
    _dashedLine(canvas, Offset(cx, cy), Offset(holdX, holdY), holdPaint);

    // labels
    _label(canvas, '$unitLabel',
        Offset(cx + 6, 12));
    _label(canvas, '↑', Offset(cx + size.width / 2 - 14, 4),
        color: Colors.black54);
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 6.0;
    const gap = 4.0;
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final ux = d.dx / len;
    final uy = d.dy / len;
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
      text: TextSpan(
          text: text, style: TextStyle(fontSize: 10, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, pos);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) =>
      old.elevUnits != elevUnits ||
      old.windUnits != windUnits ||
      old.type != type;
}
