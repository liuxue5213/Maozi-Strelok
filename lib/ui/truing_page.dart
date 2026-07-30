import 'package:flutter/material.dart';

import '../models/firearm.dart';
import '../physics/atmosphere.dart';
import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;
import '../services/shot_builder.dart';
import 'app_state.dart';

/// Drop-truing page: enter an observed impact offset at a known range, and the
/// solver finds the ballistic coefficient that reproduces it. The trued BC can
/// then be applied to the current bullet (as a custom override).
class TruingPage extends StatefulWidget {
  final AppState state;
  const TruingPage({super.key, required this.state});

  @override
  State<TruingPage> createState() => _TruingPageState();
}

class _TruingPageState extends State<TruingPage> {
  final _rangeCtrl = TextEditingController(text: '500');
  final _dropCtrl = TextEditingController(text: '-40');
  String _unit = 'in'; // in or cm
  double? _truedBc;
  double? _predictedDrop;
  String? _error;

  ShotConfig? _buildConfig() {
    final s = widget.state;
    if (!s.canCompute) return null;
    return ShotBuilder.build(
      firearm: s.firearm!,
      cartridge: s.cartridge!,
      bullet: s.bullet!,
      mod: s.mod,
      atmosphere: Atmosphere(
        temperatureC: s.temperatureC,
        pressurePa: U.Units.hpaToPa(s.pressureHpa),
        relativeHumidity: s.relativeHumidity,
        altitudeM: s.altitudeM,
      ),
      wind: Wind.calm(),
      dragModelId: s.useG7 ? 'G7' : 'G1',
      spinDrift: false,
    );
  }

  void _run() {
    setState(() => _error = null);
    final cfg = _buildConfig();
    if (cfg == null) {
      setState(() => _error = '请先在计算页选择枪械/弹药/弹头');
      return;
    }
    final rangeYd = double.tryParse(_rangeCtrl.text);
    final dropVal = double.tryParse(_dropCtrl.text);
    if (rangeYd == null || dropVal == null || rangeYd <= 0) {
      setState(() => _error = '请输入有效的距离和落点');
      return;
    }
    final rangeM = U.Units.yardsToM(rangeYd);
    // observed drop in meters; negative = below LOS
    final obsM =
        _unit == 'in' ? U.Units.inchToM(dropVal.abs()) * (dropVal < 0 ? -1 : 1)
            : dropVal / 100.0;

    final solver = BallisticsSolver(cfg);
    _predictedDrop = solver.dropAtRange(rangeM);
    final bc = solver.truedBc(rangeM: rangeM, observedDropM: obsM);
    setState(() {
      _truedBc = bc;
      if (bc == null) {
        _error = '无法在该 BC 范围内匹配实测落点（落点超出物理范围）';
      }
    });
  }

  /// Save the trued BC as a custom bullet (clone of current, new BC) so the
  /// user can select it for precise future calculations.
  void _applyTruedBc(Bullet? orig, double origBc) async {
    if (_truedBc == null || orig == null) return;
    final s = widget.state;
    final custom = Bullet(
      id: '${orig.id}-trued-${DateTime.now().millisecondsSinceEpoch}',
      manufacturer: orig.manufacturer,
      model: '${orig.model} (校准 BC=${_truedBc!.toStringAsFixed(3)})',
      caliber: orig.caliber,
      massGr: orig.massGr,
      diameterIn: orig.diameterIn,
      lengthIn: orig.lengthIn,
      bcG1: s.useG7 ? orig.bcG1 : _truedBc!,
      bcG7: s.useG7 ? _truedBc! : orig.bcG7,
      type: orig.type,
    );
    await s.db.addBullet(custom);
    s.selectBullet(custom);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存校准弹头并应用 (BC=${_truedBc!.toStringAsFixed(3)})')));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final b = s.bullet;
    final origBc = s.useG7 ? (b?.bcG7 ?? b?.bcG1 ?? 0) : (b?.bcG1 ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('弹道校准 (Truing)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(b == null
                  ? '未选择弹头'
                  : '${b.manufacturer} ${b.model} (${b.massGr}gr)'),
              subtitle: Text('当前 ${s.useG7 ? 'G7' : 'G1'} BC = ${origBc.toStringAsFixed(3)}'),
            ),
          ),
          const SizedBox(height: 12),
          const Text('输入实测数据',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _rangeCtrl,
            decoration: const InputDecoration(
                labelText: '实测距离 (yard)',
                border: OutlineInputBorder()),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dropCtrl,
                  decoration: const InputDecoration(
                      labelText: '实测落点 (负=偏低)',
                      border: OutlineInputBorder()),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _unit,
                items: const [
                  DropdownMenuItem(value: 'in', child: Text('英寸')),
                  DropdownMenuItem(value: 'cm', child: Text('厘米')),
                ],
                onChanged: (v) => setState(() => _unit = v ?? 'in'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.tune),
            label: const Text('反算修正 BC'),
            onPressed: _run,
          ),
          const SizedBox(height: 16),
          if (_predictedDrop != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前 BC 在该距离的预测落点: ${(_predictedDrop! * (_unit == 'in' ? 39.37 : 100)).toStringAsFixed(1)} $_unit'),
                    const SizedBox(height: 8),
                    if (_truedBc != null) ...[
                      Text('修正后 BC: ${_truedBc!.toStringAsFixed(3)} '
                          '(${((_truedBc! - origBc) / origBc * 100).toStringAsFixed(1)}%)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 4),
                      const Text('提示: 可将此 BC 用于该批弹药的精确计算。'
                          '建议在远程距离 (≥500yd) 实测校准。'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.save_alt),
                        label: const Text('保存为校准弹头 (自定义)'),
                        onPressed: () => _applyTruedBc(b, origBc),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ),
            ),
          if (_predictedDrop == null && _error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error, color: Colors.red),
                title: Text(_error!),
              ),
            ),
        ],
      ),
    );
  }
}
