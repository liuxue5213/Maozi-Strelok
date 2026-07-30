import 'package:flutter/material.dart';

import '../models/firearm.dart';
import '../models/modification.dart';
import '../physics/atmosphere.dart';
import '../services/shot_builder.dart';
import 'app_state.dart';

/// Modification configuration page: barrel/twist, optics/zero, muzzle device.
/// Shows live stability factor feedback.
class ModifyPage extends StatefulWidget {
  final AppState state;
  final Firearm firearm;
  const ModifyPage({super.key, required this.state, required this.firearm});

  @override
  State<ModifyPage> createState() => _ModifyPageState();
}

class _ModifyPageState extends State<ModifyPage> {
  late Modification _mod;
  late bool _customBarrel;
  late bool _customTwist;

  @override
  void initState() {
    super.initState();
    _mod = widget.state.mod;
    _customBarrel = _mod.barrelLengthIn != null;
    _customTwist = _mod.twistRateIn != null;
  }

  void _commit() {
    final m = _mod.copyWith(
      barrelLengthIn: _customBarrel ? _mod.barrelLengthIn : null,
      twistRateIn: _customTwist ? _mod.twistRateIn : null,
    );
    setState(() => _mod = m);
    widget.state.updateMod(m);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.firearm;

    // Stability preview (needs cartridge/bullet) — reuse the shared engine.
    String stabilityText = '请先选择弹药以计算稳定性';
    final ct = widget.state.cartridge;
    final b = widget.state.bullet;
    if (ct != null && b != null) {
      final sg = ShotBuilder.stabilityFactor(
        firearm: f,
        cartridge: ct,
        bullet: b,
        mod: _mod,
        atmosphere: Atmosphere.standardIcao(),
      );
      stabilityText = '稳定性 Sg = ${sg.toStringAsFixed(2)} (${_assess(sg)})';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('改装配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('枪管 / 缠距', [
            SwitchListTile(
              title: const Text('自定义枪管长度'),
              value: _customBarrel,
              onChanged: (v) => setState(() {
                _customBarrel = v;
                if (v && _mod.barrelLengthIn == null) {
                  _mod = _mod.copyWith(barrelLengthIn: f.barrelLengthIn);
                }
              }),
            ),
            if (_customBarrel)
              _sliderRow(
                label: '枪管长度',
                value: _mod.barrelLengthIn ?? f.barrelLengthIn,
                min: 4,
                max: 30,
                unit: '"',
                onChanged: (v) => setState(() => _mod = _mod.copyWith(barrelLengthIn: v)),
              )
            else
              _infoRow('枪管长度（默认）', '${f.barrelLengthIn}"'),
            SwitchListTile(
              title: const Text('自定义缠距'),
              value: _customTwist,
              onChanged: (v) => setState(() {
                _customTwist = v;
                if (v && _mod.twistRateIn == null) {
                  _mod = _mod.copyWith(twistRateIn: f.twistRateIn);
                }
              }),
            ),
            if (_customTwist)
              _sliderRow(
                label: '缠距 (in/turn)',
                value: _mod.twistRateIn ?? f.twistRateIn,
                min: 5,
                max: 16,
                unit: '"',
                step: 0.5,
                onChanged: (v) => setState(() => _mod = _mod.copyWith(twistRateIn: v)),
              )
            else
              _infoRow('缠距（默认）', '1:${f.twistRateIn}"'),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.timeline),
                title: Text(stabilityText),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _section('瞄具 / 归零', [
            _sliderRow(
              label: '瞄具高度 (bore to sight)',
              value: _mod.sightHeightIn,
              min: 0.5,
              max: 4,
              unit: '"',
              onChanged: (v) => setState(() => _mod = _mod.copyWith(sightHeightIn: v)),
            ),
            _sliderRow(
              label: '归零距离',
              value: _mod.zeroRangeYd,
              min: 25,
              max: 500,
              unit: ' yd',
              onChanged: (v) => setState(() => _mod = _mod.copyWith(zeroRangeYd: v.roundToDouble())),
            ),
          ]),
          const SizedBox(height: 12),
          _section('枪口装置', [
            Wrap(
              spacing: 8,
              children: MuzzleDevice.values.map((d) {
                return ChoiceChip(
                  label: Text(_muzzleLabel(d)),
                  selected: _mod.muzzleDevice == d,
                  onSelected: (_) => setState(() => _mod = _mod.copyWith(muzzleDevice: d)),
                );
              }).toList(),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('保存配置'),
            onPressed: _commit,
          ),
        ],
      ),
    );
  }

  String _assess(double sg) {
    if (sg < 1.0) return '不稳定';
    if (sg < 1.3) return '临界';
    if (sg < 1.5) return '稳定';
    return '最佳';
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),
              ...children,
            ],
          ),
        ),
      );

  Widget _infoRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(k)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    double step = 0.1,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.toStringAsFixed(step >= 1 ? 0 : (step >= 0.5 ? 1 : 2))}$unit'),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
