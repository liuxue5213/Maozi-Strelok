import 'package:flutter/material.dart';

import '../physics/units.dart' as U;
import 'app_state.dart';

/// Advanced Wind Kit — up to 8 user-positioned downrange wind zones, reorderable
/// by drag, with per-zone speed/direction editing. Mirrors Ballistic app's
/// "Advanced Wind Kit" feature (their standout differentiator). Each zone covers
/// a downrange segment [fromYd, toYd]; the solver picks the active zone by the
/// bullet's current downrange position during RK4 integration.
class WindZonesPage extends StatefulWidget {
  final AppState state;
  const WindZonesPage({super.key, required this.state});

  @override
  State<WindZonesPage> createState() => _WindZonesPageState();
}

const int kMaxWindZones = 8;

class _WindZonesPageState extends State<WindZonesPage> {
  late List<WindZoneInput> _zones;

  @override
  void initState() {
    super.initState();
    _zones = List.of(widget.state.windZones);
    if (_zones.isEmpty) _addZone(); // start with one starter zone
  }

  void _addZone() {
    if (_zones.length >= kMaxWindZones) return;
    setState(() {
      final lastTo = _zones.isEmpty ? 100.0 : _zones.last.toYd;
      _zones.add(WindZoneInput(
        fromYd: lastTo,
        toYd: lastTo + 200,
        speedMph: 5,
        dirDeg: 90,
      ));
    });
  }

  void _removeZone(int i) => setState(() => _zones.removeAt(i));

  void _commit() {
    widget.state.windZones = List.unmodifiable(_zones);
    widget.state.persistEnvAndShooting();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${_zones.length} 个风段')));
  }

  void _clear() {
    setState(() => _zones = []);
    widget.state.windZones = const [];
    widget.state.persistEnvAndShooting();
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _zones.length < kMaxWindZones;
    return Scaffold(
      appBar: AppBar(
        title: Text('多段风 (${_zones.length}/$kMaxWindZones)'),
        actions: [
          IconButton(
            tooltip: '添加风段',
            icon: Icon(Icons.add_circle_outline,
                color: canAdd ? null : Colors.grey),
            onPressed: canAdd ? _addZone : null,
          ),
          if (_zones.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
            ),
        ],
      ),
      body: Column(
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.air, color: Colors.blue),
              title: Text('Advanced Wind Kit'),
              subtitle: Text('沿射程分段设置风况。拖动右侧 ⋮⋮ 可调整优先级。'
                  '最多 8 段,覆盖弹道各段的风速/风向。'),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _zones.isEmpty
                ? const Center(child: Text('无风段 — 使用上方 + 添加'))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _zones.length,
                    onReorder: (oldI, newI) => setState(() {
                      if (newI > oldI) newI -= 1;
                      final item = _zones.removeAt(oldI);
                      _zones.insert(newI, item);
                    }),
                    itemBuilder: (ctx, i) {
                      final z = _zones[i];
                      return _zoneCard(i, z, Key('$i'));
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('保存并应用'),
                    onPressed: _commit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoneCard(int i, WindZoneInput z, Key key) {
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header: priority badge + drag handle + delete
            Row(
              children: [
                CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.blue,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '第 ${i + 1} 段  ·  '
                    '${z.fromYd.toStringAsFixed(0)}-${z.toYd.toStringAsFixed(0)} yd',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.drag_handle, color: Colors.grey),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  onPressed: () => _removeZone(i),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Range sliders
            _row('起点 yd', z.fromYd, 50, 2500, 10,
                (v) => setState(() => _zones[i] =
                    z.copyWith(fromYd: v))),
            _row('终点 yd', z.toYd, 50, 3000, 10,
                (v) => setState(() => _zones[i] =
                    z.copyWith(toYd: v))),
            const Divider(),
            // Wind speed + direction (display unit follows the wind-unit
            // preference set on the compute page; storage stays mph)
            _row(
                '风速 ${U.windUnitLabel(widget.state.windUnit)}',
                U.windFromMph(z.speedMph, widget.state.windUnit),
                0,
                U.windFromMph(30, widget.state.windUnit),
                0.5,
                (v) => setState(() => _zones[i] = z.copyWith(
                    speedMph: U.windToMph(v, widget.state.windUnit)))),
            Row(
              children: [
                const SizedBox(width: 70, child: Text('风向°')),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 360,
                    divisions: 72,
                    value: z.dirDeg,
                    label: '${z.dirDeg.toStringAsFixed(0)}°',
                    onChanged: (v) => setState(() => _zones[i] =
                        z.copyWith(dirDeg: v)),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text('${z.dirDeg.toStringAsFixed(0)}°',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
      String label, double value, double min, double max, double step,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label)),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            value: value.clamp(min, max),
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(value.toStringAsFixed(0),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

extension on WindZoneInput {
  WindZoneInput copyWith({
    double? fromYd,
    double? toYd,
    double? speedMph,
    double? dirDeg,
  }) =>
      WindZoneInput(
        fromYd: fromYd ?? this.fromYd,
        toYd: toYd ?? this.toYd,
        speedMph: speedMph ?? this.speedMph,
        dirDeg: dirDeg ?? this.dirDeg,
      );
}
