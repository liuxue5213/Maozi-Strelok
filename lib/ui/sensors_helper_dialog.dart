import 'package:flutter/material.dart';

import '../services/sensor_service.dart';
import 'app_state.dart';

/// A helper dialog that gathers the environment-dependent inputs the solver
/// needs (latitude, firing azimuth, line-of-sight angle) in one place. These
/// drive the Coriolis and incline corrections.
///
/// GPS (latitude) and compass (azimuth) auto-fill via [SensorService]; all
/// sensor failures degrade to a hint and manual entry keeps working.
class SensorsHelperDialog extends StatefulWidget {
  final AppState state;
  const SensorsHelperDialog({super.key, required this.state});

  @override
  State<SensorsHelperDialog> createState() => _SensorsHelperDialogState();
}

class _SensorsHelperDialogState extends State<SensorsHelperDialog> {
  late final TextEditingController _lat;
  late final TextEditingController _az;
  late final TextEditingController _los;
  late final TextEditingController _decl;
  bool _gpsBusy = false;
  bool _compassBusy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _lat = TextEditingController(text: s.latitudeDeg.toStringAsFixed(1));
    _az = TextEditingController(text: s.azimuthDeg.toStringAsFixed(0));
    _los = TextEditingController(text: s.losAngleDeg.toStringAsFixed(1));
    _decl = TextEditingController(
        text: s.magneticDeclinationDeg == 0
            ? ''
            : s.magneticDeclinationDeg.toStringAsFixed(1));
    // keep the persisted declination in sync with manual edits
    _decl.addListener(() {
      widget.state.magneticDeclinationDeg =
          double.tryParse(_decl.text) ?? 0;
    });
  }

  @override
  void dispose() {
    _lat.dispose();
    _az.dispose();
    _los.dispose();
    _decl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('射击环境参数'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('这些参数驱动科里奥利修正与仰俯角修正。'
                  '远程射击(>800yd)时建议启用科里奥利。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('启用科里奥利/Eötvös'),
                value: widget.state.useCoriolis,
                onChanged: (v) => setState(() => widget.state.useCoriolis = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _gpsBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.gps_fixed, size: 16),
                      label: const Text('GPS 定位',
                          style: TextStyle(fontSize: 12)),
                      onPressed: _gpsBusy ? null : _fillFromGps,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _compassBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.explore, size: 16),
                      label: const Text('罗盘方位',
                          style: TextStyle(fontSize: 12)),
                      onPressed: _compassBusy ? null : _fillFromCompass,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field(_lat, '纬度 (°, +北 / -南)', signed: true),
              _field(_az, '射击方位角 (°, 北=0 顺时针)', signed: true),
              _field(_decl, '磁偏角 (°, +东; 罗盘填数时自动加上)', signed: true),
              _field(_los, '射击仰俯角 (°, +上 / -下)', signed: true),
              const SizedBox(height: 8),
              const Text('提示: 方位角 = 目标相对正北的顺时针角度(罗盘读数+磁偏角)。'
                  '磁偏角可从当地地图/在线地磁模型查询，一次设置长期有效。'
                  '仰俯角 = 视线上仰为正、下俯为负(可用测角仪/余弦指示器读取)。',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final s = widget.state;
            s.latitudeDeg = double.tryParse(_lat.text) ?? s.latitudeDeg;
            s.azimuthDeg = double.tryParse(_az.text) ?? s.azimuthDeg;
            s.losAngleDeg = double.tryParse(_los.text) ?? s.losAngleDeg;
            Navigator.pop(context);
          },
          child: const Text('应用'),
        ),
      ],
    );
  }

  /// GPS auto-fill: fills latitude (and reports altitude so the shooter can
  /// enter it on the main page if trusted). Any failure shows a hint instead.
  Future<void> _fillFromGps() async {
    setState(() => _gpsBusy = true);
    final fix = await SensorService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _gpsBusy = false);
    if (fix == null) {
      _snack('无法获取定位：请检查系统定位开关与定位权限（浏览器需 HTTPS）');
      return;
    }
    _lat.text = fix.latitudeDeg.toStringAsFixed(4);
    final alt = fix.altitudeM;
    _snack(alt == null
        ? '已填入纬度 ${fix.latitudeDeg.toStringAsFixed(4)}°'
        : '已填入纬度 ${fix.latitudeDeg.toStringAsFixed(4)}°，'
            'GPS 海拔约 ${alt.toStringAsFixed(0)}m（如需可填入环境海拔）');
  }

  /// Compass auto-fill: points the phone at the target and reads the heading.
  /// The reading is magnetic north; the configured declination is added so
  /// the Coriolis azimuth gets a true-north value.
  Future<void> _fillFromCompass() async {
    setState(() => _compassBusy = true);
    final heading = await SensorService.readHeading();
    if (!mounted) return;
    setState(() => _compassBusy = false);
    if (heading == null) {
      _snack('此设备/浏览器没有可用的罗盘传感器，请手动输入方位角');
      return;
    }
    final decl = double.tryParse(_decl.text) ?? 0;
    // normalize to 0..360 (heading can read slightly negative)
    final az = (((heading + decl) % 360) + 360) % 360;
    _az.text = az.toStringAsFixed(0);
    _snack(decl.abs() < 0.05
        ? '已填入磁北方位角 ${az.toStringAsFixed(0)}°'
        : '磁北 ${heading.toStringAsFixed(0)}° + 磁偏角 ${decl.toStringAsFixed(1)}° '
            '= 真北 ${az.toStringAsFixed(0)}°');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _field(TextEditingController c, String label, {bool signed = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
        keyboardType: TextInputType.numberWithOptions(
            decimal: true, signed: signed),
      ),
    );
  }
}
