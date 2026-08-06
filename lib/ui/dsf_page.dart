import 'package:flutter/material.dart';

import '../physics/atmosphere.dart';
import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;
import '../services/shot_builder.dart';
import 'app_state.dart';

/// Drop Scale Factor (DSF) multi-point truing page. The shooter enters several
/// (range, observed drop) pairs and the solver derives per-range scale factors
/// that make the model match the observed impacts. This is more powerful than
/// single-point BC truing because it corrects regional model error (e.g. in the
/// transonic transition).
class DsfPage extends StatefulWidget {
  final AppState state;
  const DsfPage({super.key, required this.state});

  @override
  State<DsfPage> createState() => _DsfPageState();
}

class _DsfPageState extends State<DsfPage> {
  final List<Map<String, TextEditingController>> _rows = [];
  String? _error;

  void _addRow() {
    setState(() {
      _rows.add({
        'range': TextEditingController(text: '500'),
        'drop': TextEditingController(text: '-40'),
      });
    });
  }

  void _removeRow(int i) {
    setState(() {
      _rows[i]['range']!.dispose();
      _rows[i]['drop']!.dispose();
      _rows.removeAt(i);
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r['range']!.dispose();
      r['drop']!.dispose();
    }
    super.dispose();
  }

  BallisticsSolver? _solver() {
    final s = widget.state;
    if (!s.canCompute) return null;
    final cfg = ShotBuilder.build(
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
      dragModelId: s.dragModelId,
      spinDrift: false,
    );
    return BallisticsSolver(cfg);
  }

  void _compute() {
    final solver = _solver();
    if (solver == null) {
      setState(() => _error = '请先选择枪械/弹药/弹头');
      return;
    }
    final observed = <double, double>{};
    for (final r in _rows) {
      final yd = double.tryParse(r['range']!.text);
      final dropIn = double.tryParse(r['drop']!.text);
      if (yd == null || dropIn == null || yd <= 0) continue;
      observed[U.Units.yardsToM(yd)] =
          U.Units.inchToM(dropIn.abs()) * (dropIn < 0 ? -1 : 1);
    }
    if (observed.isEmpty) {
      setState(() => _error = '请至少输入一组有效的距离和落点');
      return;
    }
    final dsf = solver.computeDsf(observed);
    widget.state.dsf = dsf;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已生成 ${dsf.length} 个 DSF 修正点，将应用于弹道计算')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('多点落点校准 (DSF)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('多点落点校准'),
              subtitle: Text('输入多个距离的实测落点，系统为每个距离生成缩放因子(DSF)，'
                  '修正模型在跨音速等区域的偏差。比单点 BC 校准更精确。'),
            ),
          ),
          const SizedBox(height: 12),
          ..._rows.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: r['range'],
                      decoration: const InputDecoration(
                          labelText: '距离 yd', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: r['drop'],
                      decoration: const InputDecoration(
                          labelText: '落点 in (负=低)', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _removeRow(i),
                  ),
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加一组数据'),
              onPressed: _addRow,
            ),
          ),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: Text('点击上方添加实测数据',
                      style: TextStyle(color: Colors.grey))),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.tune),
            label: const Text('生成 DSF 并应用'),
            onPressed: _rows.isEmpty ? null : _compute,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (widget.state.dsf.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('当前应用的 DSF 修正点',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            ...widget.state.dsf.entries.map((e) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Text('${(e.key * 1.09361).toStringAsFixed(0)}yd'),
                  title: Text('缩放因子 ×${e.value.toStringAsFixed(3)}'),
                )),
            TextButton(
              onPressed: () =>
                  setState(() => widget.state.dsf = const {}),
              child: const Text('清除 DSF'),
            ),
          ],
        ],
      ),
    );
  }
}
