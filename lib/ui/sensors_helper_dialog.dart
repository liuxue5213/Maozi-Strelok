import 'package:flutter/material.dart';

import 'app_state.dart';

/// A helper dialog that gathers the environment-dependent inputs the solver
/// needs (latitude, firing azimuth, line-of-sight angle) in one place. These
/// drive the Coriolis and incline corrections.
///
/// Device auto-acquisition of GPS coordinates / compass heading / inclinometer
/// angle requires platform plugins (geolocator, sensors_plus) and per-platform
/// setup. To keep the app portable and CI-buildable without native config,
/// this dialog provides fast manual entry with a clear "auto" placeholder that
/// can be wired to plugins later.
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

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _lat = TextEditingController(text: s.latitudeDeg.toStringAsFixed(1));
    _az = TextEditingController(text: s.azimuthDeg.toStringAsFixed(0));
    _los = TextEditingController(text: s.losAngleDeg.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _lat.dispose();
    _az.dispose();
    _los.dispose();
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
              _field(_lat, '纬度 (°, +北 / -南)', signed: true),
              _field(_az, '射击方位角 (°, 北=0 顺时针)', signed: true),
              _field(_los, '射击仰俯角 (°, +上 / -下)', signed: true),
              const SizedBox(height: 8),
              const Text('提示: 方位角 = 目标相对正北的顺时针角度(罗盘读数)。'
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
