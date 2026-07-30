import 'package:flutter/material.dart';

import '../models/firearm.dart';
import '../models/modification.dart';
import 'app_state.dart';
import 'cartridge_picker_dialog.dart';
import 'modify_page.dart';
import 'result_page.dart';
import 'wind_compass.dart';

/// Environment + wind + shooting-condition input page. Lets the user pick the
/// cartridge/bullet for the selected firearm, configure conditions, then run
/// the solver and view results.
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
    _latCtrl =
        TextEditingController(text: widget.state.latitudeDeg.toStringAsFixed(1));
    _azCtrl =
        TextEditingController(text: widget.state.azimuthDeg.toStringAsFixed(0));
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
          // Loadout summary with change buttons
          _loadoutCard(s),
          const SizedBox(height: 12),
          _section('环境条件', [
            _slider('温度', s.temperatureC, -30, 50, ' °C', 1, 1,
                (v) => setState(() => s.temperatureC = v)),
            _slider('气压', s.pressureHpa, 800, 1080, ' hPa', 5, 1,
                (v) => setState(() => s.pressureHpa = v)),
            _slider('相对湿度', s.relativeHumidity * 100, 0, 100, ' %', 5, 0,
                (v) => setState(() => s.relativeHumidity = v / 100)),
            _slider('海拔', s.altitudeM, 0, 4000, ' m', 100, 0,
                (v) => setState(() => s.altitudeM = v)),
          ]),
          const SizedBox(height: 12),
          _section('风', [
            _slider('风速', s.windSpeedMph, 0, 30, ' mph', 1, 0,
                (v) => setState(() => s.windSpeedMph = v)),
            _windDial(s),
          ]),
          const SizedBox(height: 12),
          _section('射击条件', [
            SwitchListTile(
              title: const Text('启用科里奥利修正'),
              subtitle: const Text('需输入纬度与射击方位角'),
              value: s.useCoriolis,
              onChanged: (v) => setState(() => s.useCoriolis = v),
            ),
            if (s.useCoriolis) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _latCtrl,
                  decoration: const InputDecoration(
                      labelText: '纬度 (°, +北 / -南)'),
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true, decimal: true),
                  onChanged: (v) => s.latitudeDeg = double.tryParse(v) ?? 0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _azCtrl,
                  decoration: const InputDecoration(
                      labelText: '射击方位角 (°, 北=0 顺时针)'),
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true, decimal: true),
                  onChanged: (v) => s.azimuthDeg = double.tryParse(v) ?? 0,
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('使用 G7 阻力模型'),
              subtitle: Text(s.useG7
                  ? '当前: G7 (低阻船尾弹, 远程更准)'
                  : '当前: G1 (通用默认)'),
              value: s.useG7,
              onChanged: (v) => setState(() => s.useG7 = v),
            ),
            SwitchListTile(
              title: const Text('计算自旋漂移'),
              subtitle: const Text('右旋膛线弹丸向右的陀螺漂移 (远程射击)'),
              value: s.useSpinDrift,
              onChanged: (v) => setState(() => s.useSpinDrift = v),
            ),
            _slider('射击仰俯角', s.losAngleDeg, -45, 45, '°', 1, 0,
                (v) => setState(() => s.losAngleDeg = v)),
            _slider('最大射程', s.maxRangeYd, 100, 2500, ' yd', 50, 0,
                (v) => setState(() => s.maxRangeYd = v)),
            _slider('采样间隔', s.stepYd, 25, 500, ' yd', 25, 0,
                (v) => setState(() => s.stepYd = v)),
          ]),
          const SizedBox(height: 12),
          _section('改装', [
            ListTile(
              leading: const Icon(Icons.build),
              title: Text(_modSummary(s.mod, s.firearm)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ModifyPage(state: s, firearm: s.firearm!),
                  ),
                );
                setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('计算弹道'),
            onPressed: s.canCompute
                ? () {
                    s.persistEnvAndShooting();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ResultPage(state: s),
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _loadoutCard(AppState s) {
    final f = s.firearm;
    final ct = s.cartridge;
    final b = s.bullet;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f?.name ?? '未选择枪械',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const Divider(height: 16),
            // Cartridge row (tappable -> picker)
            InkWell(
              onTap: f == null
                  ? null
                  : () async {
                      final picked = await showDialog<Cartridge>(
                        context: context,
                        builder: (_) => CartridgePickerDialog(
                          state: s,
                          firearm: f,
                        ),
                      );
                      if (picked != null) {
                        s.selectCartridge(picked);
                        setState(() {});
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                        width: 72,
                        child: Text('弹药',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13))),
                    Expanded(
                      child: Text(
                        ct == null
                            ? '点此选择弹药'
                            : '${ct.designation}  (${ct.caliber})\n初速 ${ct.muzzleVelocityFps.toStringAsFixed(0)} fps @ ${ct.refBarrelLengthIn}"',
                        style: TextStyle(
                            color: ct == null ? Colors.grey : null),
                      ),
                    ),
                    const Icon(Icons.swap_horiz, size: 18),
                  ],
                ),
              ),
            ),
            // Bullet row (tappable -> picker)
            InkWell(
              onTap: f == null
                  ? null
                  : () async {
                      final picked = await showDialog<Bullet>(
                        context: context,
                        builder: (_) => BulletPickerDialog(
                          state: s,
                          caliber: ct?.caliber ?? f.compatibleCalibers.first,
                        ),
                      );
                      if (picked != null) {
                        s.selectBullet(picked);
                        setState(() {});
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                        width: 72,
                        child: Text('弹头',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13))),
                    Expanded(
                      child: Text(
                        b == null
                            ? '点此选择弹头'
                            : '${b.manufacturer} ${b.model}\n${b.massGr}gr · G1 ${b.bcG1.toStringAsFixed(3)}${b.bcG7 != null ? ' · G7 ${b.bcG7!.toStringAsFixed(3)}' : ''}',
                        style: TextStyle(
                            color: b == null ? Colors.grey : null),
                      ),
                    ),
                    const Icon(Icons.swap_horiz, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _windDial(AppState s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          WindCompass(
            windFrom: s.windDirectionDeg,
            onChanged: (deg) => setState(() => s.windDirectionDeg = deg),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('风从 ${s.windDirectionDeg.toStringAsFixed(0)}° 来',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_windLabel(s.windDirectionDeg),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(
                    '提示: 圆盘顶部 = 射击方向(目标)。\n从该方向吹来的风会把弹丸推向反方向。',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _windLabel(double deg) {
    final names = [
      '逆风 (headwind, 从目标方向吹来)',
      '右后方来风',
      '从右侧来风 (吹向左)',
      '右前方来风',
      '顺风 (tailwind, 从身后吹来)',
      '左前方来风',
      '从左侧来风 (吹向右)',
      '左后方来风'
    ];
    final idx = ((deg + 22.5) / 45).floor() % 8;
    return '${deg.toStringAsFixed(0)}° · ${names[idx]}';
  }

  String _modSummary(Modification m, Firearm? f) {
    final parts = <String>[];
    parts.add('瞄具高 ${m.sightHeightIn}"');
    parts.add('归零 ${m.zeroRangeYd}yd');
    if (m.barrelLengthIn != null) parts.add('管长 ${m.barrelLengthIn}"');
    if (m.twistRateIn != null) parts.add('缠距 1:${m.twistRateIn}"');
    if (m.muzzleDevice != MuzzleDevice.none) {
      parts.add(_muzzleLabel(m.muzzleDevice));
    }
    return parts.join('  ·  ');
  }

  String _muzzleLabel(MuzzleDevice d) => switch (d) {
        MuzzleDevice.none => '无装置',
        MuzzleDevice.flashHider => '消焰器',
        MuzzleDevice.muzzleBrake => '制退器',
        MuzzleDevice.compensator => '补偿器',
        MuzzleDevice.suppressor => '消音器',
        MuzzleDevice.linearComp => '直喷补偿',
      };

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),
              ...children,
            ],
          ),
        ),
      );

  Widget _slider(String label, double value, double min, double max, String unit,
      double step, int decimals, ValueChanged<double> onChanged) {
    final divisions = ((max - min) / step).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.toStringAsFixed(decimals)}$unit'),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions > 0 ? divisions : 1,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
