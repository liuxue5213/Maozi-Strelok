import 'package:flutter/material.dart';

import 'app_state.dart';

/// Multi-zone wind editor. Lets the shooter define a downrange wind profile:
/// a list of segments, each with its own speed and direction (e.g. headwind at
/// the firing point, crosswind over the valley, different wind near the
/// target). Mirrors the "Wind Profile Analysis" / multi-wind features of
/// Applied Ballistics and JBM.
class WindZonesPage extends StatefulWidget {
  final AppState state;
  const WindZonesPage({super.key, required this.state});

  @override
  State<WindZonesPage> createState() => _WindZonesPageState();
}

class _WindZonesPageState extends State<WindZonesPage> {
  /// One controller bundle per zone row, so editing is stable (no cursor jump).
  final List<_ZoneControllers> _ctrls = [];

  @override
  void initState() {
    super.initState();
    for (final z in widget.state.windZones) {
      _ctrls.add(_ZoneControllers.from(z));
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addZone() {
    setState(() {
      final lastTo = _ctrls.isEmpty ? '0' : _ctrls.last.to.text;
      final baseTo = (double.tryParse(lastTo) ?? 0);
      final c = _ZoneControllers();
      c.from.text = lastTo;
      c.to.text = (baseTo + 300).toStringAsFixed(0);
      c.speed.text = '5';
      c.dir.text = '90';
      _ctrls.add(c);
    });
  }

  void _removeZone(int i) {
    setState(() {
      _ctrls[i].dispose();
      _ctrls.removeAt(i);
    });
  }

  void _commit() {
    widget.state.windZones = List.unmodifiable(
      _ctrls.map((c) => WindZoneInput(
            fromYd: double.tryParse(c.from.text) ?? 0,
            toYd: double.tryParse(c.to.text) ?? 99999,
            speedMph: double.tryParse(c.speed.text) ?? 0,
            dirDeg: double.tryParse(c.dir.text) ?? 0,
          )),
    );
    widget.state.persistEnvAndShooting();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${_ctrls.length} 个风段')));
  }

  void _clear() {
    setState(() {
      for (final c in _ctrls) {
        c.dispose();
      }
      _ctrls.clear();
    });
    widget.state.windZones = const [];
    widget.state.persistEnvAndShooting();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('多段风 (Wind Zones)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('多段风'),
              subtitle: Text('按射程分段定义不同风速/风向。真实场景中射手位置、'
                  '弹道中段、目标位置的风经常不同。定义后将覆盖单一风设置。'),
            ),
          ),
          const SizedBox(height: 8),
          ..._ctrls.asMap().entries.map((e) {
            final i = e.key;
            final c = e.value;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('段 ${i + 1}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 20),
                          onPressed: () => _removeZone(i),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: _field(c.from, '起点 yd')),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _field(c.to, '终点 yd')),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: _field(c.speed, '风速 mph')),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _field(c.dir, '风向 °')),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('添加风段'),
                onPressed: _addZone,
              ),
              const Spacer(),
              if (_ctrls.isNotEmpty)
                TextButton(
                  onPressed: _clear,
                  child: const Text('清空'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('保存并应用'),
            onPressed: _commit,
          ),
          const SizedBox(height: 8),
          Text(
              _ctrls.isEmpty
                  ? '当前: 使用单一风 (在计算页设置)'
                  : '当前: ${_ctrls.length} 段风 (保存后生效)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
      ),
    );
  }
}

/// Persistent controllers for one wind-zone row.
class _ZoneControllers {
  final TextEditingController from = TextEditingController();
  final TextEditingController to = TextEditingController();
  final TextEditingController speed = TextEditingController();
  final TextEditingController dir = TextEditingController();

  _ZoneControllers();

  factory _ZoneControllers.from(WindZoneInput z) {
    final c = _ZoneControllers();
    c.from.text = z.fromYd.toStringAsFixed(0);
    c.to.text = z.toYd.toStringAsFixed(0);
    c.speed.text = z.speedMph.toStringAsFixed(1);
    c.dir.text = z.dirDeg.toStringAsFixed(0);
    return c;
  }

  void dispose() {
    from.dispose();
    to.dispose();
    speed.dispose();
    dir.dispose();
  }
}
