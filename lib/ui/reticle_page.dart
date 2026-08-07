import 'package:flutter/material.dart';

import '../models/reticle.dart';
import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;
import 'app_state.dart';
import 'reticle_painter.dart';
import 'reticle_picker_dialog.dart';

/// Reticle simulation page. Renders ANY reticle from the real-scope reticle
/// library (Mil-Dot, ACOG, EBR-2C, TMR, MOAR, Horus, PSO-1, ...), honors FFP vs
/// SFP magnification scaling, and overlays the ballistic hold point computed
/// from the solved trajectory — Strelok's headline "see holdovers on the
/// reticle without turning knobs" feature, now with a real reticle library.
class ReticlePage extends StatefulWidget {
  final AppState state;
  final List<TrajectoryPoint> traj;
  const ReticlePage({super.key, required this.state, required this.traj});

  @override
  State<ReticlePage> createState() => _ReticlePageState();
}

class _ReticlePageState extends State<ReticlePage> {
  /// Selected reticle (defaults to USMC Mil-Dot).
  ReticleSpec? _reticle;
  double _targetYd = 500;
  double _magnification = 10; // scope zoom (affects SFP reticles)
  /// If true, hold values are shown in the reticle's native unit; else toggle.
  bool _useReticleUnit = true;

  @override
  void initState() {
    super.initState();
    _reticle = widget.state.db.reticle('usmc-mildot') ??
        (widget.state.db.reticles.isNotEmpty
            ? widget.state.db.reticles.first
            : null);
  }

  @override
  Widget build(BuildContext context) {
    final traj = widget.traj;
    final sys = widget.state.unitSystem;
    final targetM = U.Units.yardsToM(_targetYd);
    final pt = traj.isEmpty
        ? null
        : traj.reduce((TrajectoryPoint a, TrajectoryPoint b) =>
            (a.range - targetM).abs() < (b.range - targetM).abs() ? a : b);

    double elevRad = 0, windRad = 0;
    if (pt != null && pt.range > 1) {
      elevRad = pt.comeUpRad;
      windRad = pt.windage / pt.range;
    }

    // Convert hold to the reticle's native unit (MIL or MOA).
    final reticle = _reticle;
    final useMoa = reticle?.unit == 'MOA';
    final elevUnits = useMoa ? U.Units.radToMoa(elevRad) : U.Units.radToMil(elevRad);
    final windUnits = useMoa ? U.Units.radToMoa(windRad) : U.Units.radToMil(windRad);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分划板模拟'),
        actions: [
          IconButton(
            tooltip: '从分划板库选择',
            icon: const Icon(Icons.library_books),
            onPressed: () async {
              final picked = await showDialog<ReticleSpec>(
                context: context,
                builder: (_) => ReticlePickerDialog(
                  state: widget.state,
                  currentId: _reticle?.id,
                ),
              );
              if (picked != null) setState(() => _reticle = picked);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Reticle name + focal plane info bar
          if (reticle != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.blue.withValues(alpha: 0.08),
              child: Text(
                '${reticle.name} · ${reticle.manufacturer} · ${reticle.unit} · ${reticle.focalPlane}'
                '${reticle.focalPlane == 'SFP' ? ' (@${reticle.sfpRefMag}x)' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          // Magnification slider (matters for SFP)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Text('放大倍率: ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 25,
                    divisions: 24,
                    value: _magnification.clamp(1.0, 25.0),
                    label: '${_magnification.round()}x',
                    onChanged: (v) => setState(() => _magnification = v),
                  ),
                ),
                Text('${_magnification.round()}x',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (reticle?.focalPlane == 'FFP')
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('(FFP)', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
              ],
            ),
          ),
          // Target distance
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Text('目标距离: ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    min: 25,
                    max: (widget.state.maxRangeYd).clamp(25.0, 2000.0),
                    divisions:
                        (((widget.state.maxRangeYd).clamp(25.0, 2000.0) - 25) / 5).round(),
                    value: _targetYd.clamp(25.0, widget.state.maxRangeYd),
                    label: '${_targetYd.toStringAsFixed(0)} yd',
                    onChanged: (v) => setState(() => _targetYd = v),
                  ),
                ),
                InkWell(
                  onTap: () => _editTargetYd(),
                  child: Text('${_targetYd.toStringAsFixed(0)}yd ✎',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: Colors.blue)),
                ),
              ],
            ),
          ),
          // Reticle rendering
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: reticle == null
                      ? const Center(child: Text('无分划板'))
                      : CustomPaint(
                          painter: ReticleLibraryPainter(
                            spec: reticle,
                            elevUnits: elevUnits,
                            windUnits: windUnits,
                            magnification: _magnification,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // readout card
          if (pt != null && reticle != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                          '目标 ${_targetYd.toStringAsFixed(0)}yd  修正点 (${reticle.unit})',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _readout('高低',
                              '${elevUnits.toStringAsFixed(1)} ${reticle.unit}',
                              elevRad > 0 ? '↑ 抬高' : '↓ 压低'),
                          _readout('风向',
                              '${windUnits.toStringAsFixed(1)} ${reticle.unit}',
                              windRad >= 0 ? '→ 向右' : '← 向左'),
                          _readout('剩余速度', Fmt_velocity(pt.speed, sys), ''),
                          _readout('飞行时间', '${pt.timeOfFlight.toStringAsFixed(2)}s', ''),
                        ],
                      ),
                      if (reticle.notes != null) ...[
                        const SizedBox(height: 6),
                        Text(reticle.notes!,
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                            textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String Fmt_velocity(double mps, U.UnitSystem sys) => sys == U.UnitSystem.imperial
      ? '${(mps * 3.28084).toStringAsFixed(0)} fps'
      : '${mps.toStringAsFixed(0)} m/s';

  void _editTargetYd() {
    final ctrl = TextEditingController(text: _targetYd.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('输入目标距离'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '距离 (yd)',
            suffixText: 'yd',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v >= 1) {
                setState(() => _targetYd = v.clamp(1.0, widget.state.maxRangeYd));
              }
              if (dctx.mounted) Navigator.pop(dctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

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
