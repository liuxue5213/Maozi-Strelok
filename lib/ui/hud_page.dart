import 'package:flutter/material.dart';

import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;
import 'app_state.dart';

/// HUD (Heads-Up Display) — Ballistic app's signature feature.
///
/// Big, glanceable numbers for the single-shot firing solution:
/// elevation hold, windage hold, and moving-target lead — all in the
/// shooter's chosen unit (MOA or MIL), with one-touch atmospheric updates.
///
/// Designed for fast field use: high contrast, large type, minimal chrome.
class HudPage extends StatefulWidget {
  final AppState state;
  final List<TrajectoryPoint> traj;
  const HudPage({super.key, required this.state, required this.traj});

  @override
  State<HudPage> createState() => _HudPageState();
}

class _HudPageState extends State<HudPage> {
  bool _showMoa = false;
  double _rangeYd = 500;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final sys = s.unitSystem;
    final traj = widget.traj;

    // nearest trajectory point to the selected range
    final rangeM = U.Units.yardsToM(_rangeYd);
    final pt = traj.isEmpty
        ? null
        : traj.reduce((TrajectoryPoint a, TrajectoryPoint b) =>
            (a.range - rangeM).abs() < (b.range - rangeM).abs() ? a : b);

    // sight corrections in the chosen unit
    double elev = 0, wind = 0, lead = 0, clicks = 0;
    String elevDir = '', windDir = '';
    if (pt != null && pt.range > 1) {
      final eRad = pt.comeUpRad;
      final wRad = pt.windage / pt.range;
      elev = _showMoa ? U.Units.radToMoa(eRad) : U.Units.radToMil(eRad);
      wind = _showMoa ? U.Units.radToMoa(wRad) : U.Units.radToMil(wRad);
      elevDir = elev >= 0 ? 'UP' : 'DOWN';
      windDir = wind >= 0 ? 'RIGHT' : 'LEFT';
      // linear lead at the configured target speed
      if (s.targetSpeedMph > 0) {
        final targetMps = U.Units.mphToMps(s.targetSpeedMph);
        lead = targetMps * pt.timeOfFlight;
      }
      // scope clicks
      if (s.clickMoa > 0 && elev != 0) {
        final absUnits = elev.abs();
        clicks = absUnits / s.clickMoa;
      }
    }

    final unit = _showMoa ? 'MOA' : 'MIL';
    final sysUnit = sys == U.UnitSystem.imperial;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('HUD', style: TextStyle(color: Colors.white)),
        actions: [
          // MOA / MIL toggle
          TextButton(
            onPressed: () => setState(() => _showMoa = !_showMoa),
            child: Text(_showMoa ? 'MOA' : 'MIL',
                style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // range selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('距离',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Expanded(
                    child: Slider(
                      min: 25,
                      max: (s.maxRangeYd).clamp(25.0, 2000.0),
                      divisions:
                          (((s.maxRangeYd).clamp(25.0, 2000.0) - 25) / 5).round(),
                      value: _rangeYd.clamp(25.0, s.maxRangeYd),
                      onChanged: (v) => setState(() => _rangeYd = v),
                    ),
                  ),
                  Text('${_rangeYd.toStringAsFixed(0)} yd',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            // ── BIG NUMBER: Elevation ──
            Expanded(
              child: _hudValue(
                label: 'ELEVATION',
                value: elev,
                unit: unit,
                dir: elevDir,
                clicks: clicks,
                color: Colors.amber,
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            // ── BIG NUMBER: Windage ──
            Expanded(
              child: _hudValue(
                label: 'WINDAGE',
                value: wind,
                unit: unit,
                dir: windDir,
                color: Colors.cyanAccent,
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            // ── Secondary readouts: Lead + Conditions ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: _smallReadout(
                      'LEAD',
                      lead > 0
                          ? '${(lead * (sysUnit ? 39.37 : 100)).toStringAsFixed(1)} ${sysUnit ? 'in' : 'cm'}'
                          : '-',
                    ),
                  ),
                  Expanded(child: _smallReadout('SPEED', pt == null ? '-' : (sysUnit ? '${(pt.speed * 3.28084).toStringAsFixed(0)} fps' : '${pt.speed.toStringAsFixed(0)} m/s'))),
                  Expanded(child: _smallReadout('TOF', pt == null ? '-' : '${pt.timeOfFlight.toStringAsFixed(2)} s')),
                ],
              ),
            ),
            // Atmospheric reminder
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${s.temperatureC.toStringAsFixed(0)}°C  ${s.pressureHpa.toStringAsFixed(0)}hPa  '
                '海拔${s.altitudeM.toStringAsFixed(0)}m  风${s.windSpeedMph.toStringAsFixed(0)}mph@${s.windDirectionDeg.toStringAsFixed(0)}°',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudValue({
    required String label,
    required double value,
    required String unit,
    required String dir,
    double clicks = 0,
    required Color color,
  }) {
    final display = '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 14,
                  letterSpacing: 4)),
          const SizedBox(height: 8),
          Text(display,
              style: TextStyle(
                  color: color,
                  fontSize: 96,
                  fontWeight: FontWeight.w200,
                  height: 1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$dir $unit',
                  style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 20)),
              if (clicks > 0) ...[
                Text('  ·  ',
                    style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 20)),
                Text('${clicks.toStringAsFixed(0)} clicks',
                    style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 20)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallReadout(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
