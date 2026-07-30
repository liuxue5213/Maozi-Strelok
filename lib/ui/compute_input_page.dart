import 'package:flutter/material.dart';

import 'app_state.dart';
import 'result_page.dart';

/// Environment + wind + shooting-condition input page. Runs the solver and
/// navigates to the result page.
class ComputeInputPage extends StatefulWidget {
  final AppState state;
  const ComputeInputPage({super.key, required this.state});

  @override
  State<ComputeInputPage> createState() => _ComputeInputPageState();
}

class _ComputeInputPageState extends State<ComputeInputPage> {
  late final TextEditingController _latCtrl;
  late final TextEditingController _azCtrl;

  @override
  void initState() {
    super.initState();
    _latCtrl = TextEditingController(text: widget.state.latitudeDeg.toStringAsFixed(1));
    _azCtrl = TextEditingController(text: widget.state.azimuthDeg.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _azCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: const Text('弹道计算')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          Card(
            child: ListTile(
              leading: const Icon(Icons.gps_fixed),
              title: Text(s.firearm?.name ?? '未选择'),
              subtitle: Text(
                '${s.cartridge?.designation ?? '-'}  ·  ${s.bullet != null ? '${s.bullet!.manufacturer} ${s.bullet!.model}' : '-'}',
              ),
            ),
          ),
          const SizedBox(height: 12),

          _section('环境条件', [
            _slider('温度', s.temperatureC, -30, 50, ' °C',
                (v) => setState(() => s.temperatureC = v)),
            _slider('气压', s.pressureHpa, 800, 1080, ' hPa',
                (v) => setState(() => s.pressureHpa = v)),
            _slider('相对湿度', s.relativeHumidity * 100, 0, 100, ' %',
                (v) => setState(() => s.relativeHumidity = v / 100)),
            _slider('海拔', s.altitudeM, 0, 4000, ' m',
                (v) => setState(() => s.altitudeM = v)),
          ]),
          const SizedBox(height: 12),

          _section('风', [
            _slider('风速', s.windSpeedMph, 0, 30, ' mph',
                (v) => setState(() => s.windSpeedMph = v)),
            _slider('风向 (从哪个方向吹来)', s.windDirectionDeg, 0, 359, '°',
                (v) => setState(() => s.windDirectionDeg = v)),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Text(
                _windLabel(s.windDirectionDeg),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
          const SizedBox(height: 12),

          _section('射击条件', [
            SwitchListTile(
              title: const Text('启用科里奥利修正'),
              value: s.useCoriolis,
              onChanged: (v) => setState(() => s.useCoriolis = v),
            ),
            if (s.useCoriolis) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _latCtrl,
                  decoration: const InputDecoration(labelText: '纬度 (°)'),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  onChanged: (v) => s.latitudeDeg = double.tryParse(v) ?? 0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _azCtrl,
                  decoration: const InputDecoration(labelText: '射击方位角 (°, 北=0)'),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  onChanged: (v) => s.azimuthDeg = double.tryParse(v) ?? 0,
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('使用 G7 阻力模型'),
              value: s.useG7,
              onChanged: (v) => setState(() => s.useG7 = v),
            ),
            _slider('最大射程', s.maxRangeYd, 100, 2500, ' yd',
                (v) => setState(() => s.maxRangeYd = (v / 50).round() * 50.toDouble())),
            _slider('采样间隔', s.stepYd, 25, 500, ' yd',
                (v) => setState(() => s.stepYd = (v / 25).round() * 25.toDouble())),
          ]),
          const SizedBox(height: 24),

          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('计算弹道'),
            onPressed: s.canCompute
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ResultPage(state: s),
                      ),
                    )
                : null,
          ),
        ],
      ),
    );
  }

  String _windLabel(double deg) {
    final names = [
      '顺风 (tailwind)',
      '右后方来风',
      '从右侧来风 (吹向左)',
      '右前方来风',
      '逆风 (headwind)',
      '左前方来风',
      '从左侧来风 (吹向右)',
      '左后方来风'
    ];
    final idx = ((deg + 22.5) / 45).floor() % 8;
    return '${deg.toStringAsFixed(0)}° · ${names[idx]}';
  }

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),
              ...children,
            ],
          ),
        ),
      );

  Widget _slider(String label, double value, double min, double max, String unit,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.toStringAsFixed(unit == '°' ? 0 : 1)}$unit'),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / (unit == '°' ? 1 : (max > 100 ? 5 : 1))).round().clamp(1, 100000),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
