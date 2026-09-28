import 'package:flutter/material.dart';

import '../models/firearm.dart';
import '../models/modification.dart';
import '../physics/atmosphere.dart';
import '../physics/drag_models.dart';
import '../physics/units.dart' as U;
import 'app_state.dart';
import 'cartridge_picker_dialog.dart';
import 'mil_ranging_dialog.dart';
import 'modify_page.dart';
import 'result_page.dart';
import 'sensors_helper_dialog.dart';
import 'wind_compass.dart';
import 'wind_zones_page.dart';

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

  /// Cached text controllers/focus nodes for the numeric fields, keyed by
  /// field name. Creating a controller inside build() would reset the field on
  /// every setState (slider drag, toggle…) — so they live here for the page
  /// lifetime.
  final Map<String, TextEditingController> _numCtrls = {};
  final Map<String, FocusNode> _numFocus = {};

  TextEditingController _numCtrl(String key, String text) {
    final c =
        _numCtrls.putIfAbsent(key, () => TextEditingController(text: text));
    _numFocus.putIfAbsent(key, () => FocusNode());
    if (c.text != text) {
      // Sync for external value changes (e.g. profile restore) unless the user
      // is mid-edit in this exact field. Deferred to after the build because
      // mutating a controller's text during build is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!(_numFocus[key]?.hasFocus ?? false) && c.text != text) {
          c.text = text;
        }
      });
    }
    return c;
  }

  FocusNode _numFocusNode(String key) =>
      _numFocus.putIfAbsent(key, () => FocusNode());

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
    for (final c in _numCtrls.values) {
      c.dispose();
    }
    for (final f in _numFocus.values) {
      f.dispose();
    }
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
            _slider('温度', s.temperatureC, -40, 55, ' °C', 0.5, 1,
                (v) => setState(() => s.temperatureC = v)),
            _slider('气压', s.pressureHpa, 800, 1080, ' hPa', 1, 1,
                (v) => setState(() => s.pressureHpa = v)),
            _slider('相对湿度', s.relativeHumidity * 100, 0, 100, ' %', 1, 0,
                (v) => setState(() => s.relativeHumidity = v / 100)),
            _slider('海拔', s.altitudeM, 0, 4000, ' m', 10, 0,
                (v) => setState(() => s.altitudeM = v.roundToDouble())),
            ListTile(
              dense: true,
              leading: const Icon(Icons.terrain, size: 20),
              title: Text(
                  '密度高度: ${_densityAltitudeText(s)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  '由当前温/压/湿/海拔换算，弹道按此空气密度求解'),
            ),
          ]),
          const SizedBox(height: 12),
          _section('风', [
            Row(
              children: [
                const Text('风速单位'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: s.windUnit,
                  items: const [
                    DropdownMenuItem(value: 'mph', child: Text('mph')),
                    DropdownMenuItem(value: 'ms', child: Text('m/s')),
                    DropdownMenuItem(value: 'kmh', child: Text('km/h')),
                  ],
                  onChanged: (v) =>
                      setState(() => s.windUnit = v ?? 'mph'),
                ),
                const Spacer(),
                Text('内部换算统一为 mph',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
            _slider(
                '风速',
                U.windFromMph(s.windSpeedMph, s.windUnit),
                0,
                U.windFromMph(30, s.windUnit),
                ' ${U.windUnitLabel(s.windUnit)}',
                s.windUnit == 'ms' ? 0.2 : 0.5,
                1,
                (v) => setState(
                    () => s.windSpeedMph = U.windToMph(v, s.windUnit))),
            _windDial(s),
            ListTile(
              dense: true,
              leading: const Icon(Icons.air, size: 20),
              title: Text(s.windZones.isEmpty
                  ? '多段风: 未启用 (单一风)'
                  : '多段风: ${s.windZones.length} 段已生效'),
              subtitle: const Text('沿弹道分段定义不同风速/风向'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => WindZonesPage(state: s)),
                );
                setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 12),
          _section('射击条件', [
            SwitchListTile(
              title: const Text('启用科里奥利修正'),
              subtitle: const Text('需输入纬度与射击方位角'),
              value: s.useCoriolis,
              onChanged: (v) => setState(() => s.useCoriolis = v),
            ),
            // quick environment params helper (lat / az / incline in one place)
            ListTile(
              dense: true,
              leading: const Icon(Icons.explore, size: 20),
              title: const Text('射击环境参数 (纬度/方位角/仰俯角)'),
              subtitle: const Text('一键设置科里奥利与仰俯角参数'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await showDialog(
                  context: context,
                  builder: (_) => SensorsHelperDialog(state: s),
                );
                _latCtrl.text = s.latitudeDeg.toStringAsFixed(1);
                _azCtrl.text = s.azimuthDeg.toStringAsFixed(0);
                setState(() {});
              },
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
            // Drag model selector (G1..GL)
            Row(
              children: [
                const Text('阻力模型'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: s.dragModelId,
                    items: dragModelIds
                        .map((id) => DropdownMenuItem(
                              value: id,
                              child: Text('$id 阻力函数'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      if (v != null) s.dragModelId = v;
                    }),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                  'G1=通用, G7=低阻船尾(远程), G2=重型AP, G5=短船尾, '
                  'G6/G8=平头, GI=Ingalls, GL=钝头软尖',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
            // Gentle suggestion when the selected bullet has a measured G7 BC
            // (modern boat-tail bullets track the G7 standard far better).
            if ((s.bullet?.bcG7 ?? null) != null && s.dragModelId != 'G7')
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          '此弹有实测 G7 BC (${s.bullet!.bcG7!.toStringAsFixed(3)})，'
                          '船尾弹建议用 G7 模型',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: () =>
                          setState(() => s.dragModelId = 'G7'),
                      child: const Text('切换',
                          style:
                              TextStyle(fontSize: 12, color: Colors.orange)),
                    ),
                  ],
                ),
              ),
            SwitchListTile(
              title: const Text('计算自旋漂移'),
              subtitle: const Text('右旋膛线弹丸向右的陀螺漂移 (远程射击)'),
              value: s.useSpinDrift,
              onChanged: (v) => setState(() => s.useSpinDrift = v),
            ),
            SwitchListTile(
              title: const Text('计算气动跳跃'),
              subtitle: const Text('侧风引起的垂直偏移 (高级修正)'),
              value: s.useAeroJump,
              onChanged: (v) => setState(() => s.useAeroJump = v),
            ),
            _slider('射击仰俯角', s.losAngleDeg, -45, 45, '°', 1, 1,
                (v) => setState(() => s.losAngleDeg = v)),
            _slider('移动目标速度', s.targetSpeedMph, 0, 30, ' mph', 0.5, 1,
                (v) => setState(() => s.targetSpeedMph = v)),
            _slider('最大射程', s.maxRangeYd, 100, 2500, ' yd', 10, 0,
                (v) => setState(() => s.maxRangeYd = v)),
            _slider('采样间隔', s.stepYd, 10, 500, ' yd', 5, 0,
                (v) => setState(() => s.stepYd = v)),
            const SizedBox(height: 8),
            _multiTargetsEditor(s),
            const SizedBox(height: 8),
            _chronoField(s),
            const SizedBox(height: 8),
            _powderTempFields(s),
            const SizedBox(height: 8),
            _slider('枪身倾斜角 (Cant)', s.cantAngleDeg, -15, 15, '°', 1, 0,
                (v) => setState(() => s.cantAngleDeg = v)),
            Row(
              children: [
                const Text('瞄具点击值'),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: s.clickMoa,
                  items: const [
                    DropdownMenuItem(value: 0.25, child: Text('1/4 MOA')),
                    DropdownMenuItem(value: 0.5, child: Text('1/2 MOA')),
                    DropdownMenuItem(value: 0.125, child: Text('1/8 MOA')),
                    DropdownMenuItem(value: 1.0, child: Text('1 MOA')),
                  ],
                  onChanged: (v) => setState(() => s.clickMoa = v ?? 0.25),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Mil-ranging calculator
            ListTile(
              dense: true,
              leading: const Icon(Icons.straighten, size: 20),
              title: const Text('分划板测距 (Mil-Ranging)'),
              subtitle: const Text('用已知尺寸目标 + 分划板读数反算距离'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final r = await showDialog<double>(
                  context: context,
                  builder: (_) => const MilRangingDialog(),
                );
                if (r != null) {
                  // add as a target
                  final list = s.customTargetsYd.toList()..add(r);
                  list.sort();
                  setState(() => s.customTargetsYd = list);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已添加目标 ${r.toStringAsFixed(0)}yd')));
                }
              },
            ),
            // Zero Atmosphere
            SwitchListTile(
              title: const Text('归零大气修正'),
              subtitle: const Text('远程归零(≥400yd)时，校正射击时与归零时空气密度差异'),
              value: s.useZeroAtmo,
              onChanged: (v) => setState(() => s.useZeroAtmo = v),
            ),
            if (s.useZeroAtmo)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _miniNumField('归零温度°C', s.zeroTempC,
                        (v) => setState(() => s.zeroTempC = v)),
                    _miniNumField('归零气压hPa', s.zeroPressureHpa,
                        (v) => setState(() => s.zeroPressureHpa = v)),
                    _miniNumField('归零湿度%', s.zeroHumidity * 100,
                        (v) => setState(() => s.zeroHumidity = v / 100)),
                    _miniNumField('归零海拔m', s.zeroAltitudeM.toDouble(),
                        (v) => setState(() => s.zeroAltitudeM = v)),
                  ],
                ),
              ),
            // Scope correction factor
            ExpansionTile(
              dense: true,
              title: const Text('瞄具跟踪修正 (Tall Target Test)',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text('实测每click值偏差，远程精度修正', style: TextStyle(fontSize: 11)),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _miniNumField('高低修正系数 (1.0=完美)', s.scopeElevCorrection,
                    (v) => setState(() => s.scopeElevCorrection = v)),
                _miniNumField('风向修正系数 (1.0=完美)', s.scopeWindCorrection,
                    (v) => setState(() => s.scopeWindCorrection = v)),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      '在 tall target test 中实测: 打已知距离的MOA数，测弹着位移。'
                      '系数 = 应打MOA / 实打MOA。<1 = 镜架移动多于标称(每click偏少)。',
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          _section('命中率 (Hit Probability)', [
            _slider('目标尺寸 (直径)', s.targetSizeIn, 2, 48, ' in', 1, 0,
                (v) => setState(() => s.targetSizeIn = v)),
            _slider('枪械精度 (1σ MOA)', s.gunAccuracyMoa, 0.1, 4, ' MOA', 0.1, 1,
                (v) => setState(() => s.gunAccuracyMoa = v)),
            _slider('射手误差 (1σ MOA)', s.shooterErrorMoa, 0, 3, ' MOA', 0.1, 1,
                (v) => setState(() => s.shooterErrorMoa = v)),
            _slider('测风误差 (1σ mph)', s.windErrorMph, 0, 10, ' mph', 0.5, 1,
                (v) => setState(() => s.windErrorMph = v)),
            _slider('测距误差 (1σ yd)', s.rangeErrorYd, 0, 50, ' yd', 1, 0,
                (v) => setState(() => s.rangeErrorYd = v)),
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
                ? () => _startCompute()
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

  /// Density altitude for the current conditions, shown in the environment
  /// card (Applied Ballistics-style DA workflow).
  String _densityAltitudeText(AppState s) {
    final atmo = Atmosphere(
      temperatureC: s.temperatureC,
      pressurePa: U.Units.hpaToPa(s.pressureHpa),
      relativeHumidity: s.relativeHumidity,
      altitudeM: s.altitudeM,
    );
    final daM = atmo.densityAltitudeM;
    return '${daM.toStringAsFixed(0)} m (${(daM * 3.28084).toStringAsFixed(0)} ft)';
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

  /// Editor for the multi-target quick-reference list.
  Widget _multiTargetsEditor(AppState s) {
    final presets = [100, 200, 300, 400, 500, 600, 800, 1000];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('多目标快速修正 (可选)',
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final yd in presets)
              FilterChip(
                label: Text('${yd}yd'),
                selected: s.customTargetsYd.contains(yd.toDouble()),
                onSelected: (sel) => setState(() {
                  final list = s.customTargetsYd.toList();
                  if (sel) {
                    list.add(yd.toDouble());
                    list.sort();
                  } else {
                    list.remove(yd.toDouble());
                  }
                  s.customTargetsYd = list;
                }),
              ),
          ],
        ),
        if (s.customTargetsYd.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text('已选 ${s.customTargetsYd.length} 个目标',
                    style: const TextStyle(fontSize: 11)),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      setState(() => s.customTargetsYd = const []),
                  child: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Chronograph velocity input: overrides the cartridge nominal MV when set.
  Widget _chronoField(AppState s) {
    return Row(
      children: [
        const Icon(Icons.speed, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              labelText: '测速仪初速 (fps, 0=用标称)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: _numCtrl('chrono',
                s.chronoVelocityFps == 0
                    ? ''
                    : s.chronoVelocityFps.toStringAsFixed(0)),
            focusNode: _numFocusNode('chrono'),
            onChanged: (v) => s.chronoVelocityFps = double.tryParse(v) ?? 0,
          ),
        ),
      ],
    );
  }

  /// Powder temperature sensitivity inputs: chrono-time temp + fps/°F rate.
  Widget _powderTempFields(AppState s) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              labelText: '测速时温度 °F',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(
                signed: true, decimal: true),
            controller: _numCtrl('powderTemp',
                s.powderTempF == 0 ? '' : s.powderTempF.toStringAsFixed(0)),
            focusNode: _numFocusNode('powderTemp'),
            onChanged: (v) => s.powderTempF = double.tryParse(v) ?? 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              labelText: '初速系数 fps/°F',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            controller: _numCtrl('mvSens',
                s.mvTempSensitivityFpsPerF == 0
                    ? ''
                    : s.mvTempSensitivityFpsPerF.toStringAsFixed(2)),
            focusNode: _numFocusNode('mvSens'),
            onChanged: (v) =>
                s.mvTempSensitivityFpsPerF = double.tryParse(v) ?? 0,
          ),
        ),
      ],
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

  /// Slider + tappable value field. The value text is tappable to open a
  /// numeric input dialog, so the shooter can enter precise decimal values
  /// (e.g. altitude 1234 m, temperature 21.5 °C) instead of being limited to
  /// the slider's coarse steps — matching Strelok's editable inputs.
  Widget _slider(String label, double value, double min, double max, String unit,
      double step, int decimals, ValueChanged<double> onChanged) {
    final divisions = ((max - min) / step).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _editValueDialog(label, value, min, max, unit,
                decimals, onChanged),
            child: Row(
              children: [
                Text('$label: '),
                Text('${value.toStringAsFixed(decimals)}$unit',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.blue)),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 14, color: Colors.blue),
              ],
            ),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions > 0 ? divisions : 1,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// Numeric edit dialog: lets the user type an exact value (with decimals),
  /// validated against [min]/[max]. Replaces the slider-only limitation.
  void _editValueDialog(String label, double current, double min, double max,
      String unit, int decimals, ValueChanged<double> onChanged) {
    final ctrl =
        TextEditingController(text: current.toStringAsFixed(decimals));
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('输入 $label'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(
            labelText: '$label ($min ~ $max$unit)',
            suffixText: unit,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v == null) {
                ScaffoldMessenger.of(dctx).showSnackBar(
                    const SnackBar(content: Text('请输入有效数字')));
                return;
              }
              final clamped = v.clamp(min, max);
              onChanged(clamped);
              Navigator.pop(dctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// Start ballistic computation. Pushes the result page immediately — the
  /// ResultPage itself shows a prominent "正在计算弹道…" loading screen while
  /// the RK4 + WEZ solve runs (it was made async so the UI stays responsive),
  /// so the user never mistakes computation for a freeze.
  void _startCompute() {
    final s = widget.state;
    s.persistEnvAndShooting();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultPage(state: s)),
    );
  }

  /// Compact numeric input field with a label, used in dense option panels
  /// (zero atmosphere, scope correction). Parses the typed value as a double.
  Widget _miniNumField(
      String label, double value, ValueChanged<double> onChanged) {
    return SizedBox(
      width: 140,
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        controller: _numCtrl(label, value.toStringAsFixed(2)),
        focusNode: _numFocusNode(label),
        onChanged: (v) {
          final d = double.tryParse(v);
          if (d != null) onChanged(d);
        },
      ),
    );
  }
}
