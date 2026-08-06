import 'package:flutter/material.dart';

import '../physics/units.dart' as U;

/// Reticle-ranging calculator: estimate the distance to a target of known
/// size using its angular subtension in the scope (MIL or MOA). Mirrors the
/// "Distance Calculator" / mil-ranging feature of Strelok and Applied
/// Ballistics.
///
///   distance = targetSize / angularSubtension   (same units)
///   in MIL:  yards = targetIn / mil * 27.78 ; meters = targetCm / mil * 10
///   in MOA:  yards = targetIn / moa * 100 ;  meters = targetCm / moa * 2.908
class MilRangingDialog extends StatefulWidget {
  const MilRangingDialog({super.key});

  @override
  State<MilRangingDialog> createState() => _MilRangingDialogState();
}

class _MilRangingDialogState extends State<MilRangingDialog> {
  /// 'mil' | 'moa'
  String _unit = 'mil';
  /// 'm' | 'yd'
  String _distUnit = 'yd';
  /// 'cm' | 'in'
  String _sizeUnit = 'in';
  final _sizeCtrl = TextEditingController(text: '12');
  final _angleCtrl = TextEditingController(text: '2');

  double get _rangeYd {
    final size = double.tryParse(_sizeCtrl.text) ?? 0;
    final ang = double.tryParse(_angleCtrl.text) ?? 0;
    if (ang <= 0) return 0;
    // convert size to inches
    final sizeIn = _sizeUnit == 'in' ? size : size / 2.54;
    if (_unit == 'mil') {
      // 1 MIL ≈ 3.6 in at 100 yd => yd = in/mil * 27.78
      return sizeIn / ang * 27.778;
    } else {
      // 1 MOA ≈ 1.047 in at 100 yd; shooter's MOA => yd = in/moa * 100
      return sizeIn / ang * 95.49; // true MOA
    }
  }

  @override
  Widget build(BuildContext context) {
    final rangeYd = _rangeYd;
    final rangeM = U.Units.yardsToM(rangeYd);
    return AlertDialog(
      title: const Text('分划板测距 (Mil-Ranging)'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('用已知尺寸的目标 + 分划板读数反算距离。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Row(children: [
                const Text('角度单位'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _unit,
                  items: const [
                    DropdownMenuItem(value: 'mil', child: Text('MIL')),
                    DropdownMenuItem(value: 'moa', child: Text('MOA')),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? 'mil'),
                ),
              ]),
              Row(children: [
                const Text('目标尺寸'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _sizeUnit,
                  items: const [
                    DropdownMenuItem(value: 'in', child: Text('英寸')),
                    DropdownMenuItem(value: 'cm', child: Text('厘米')),
                  ],
                  onChanged: (v) => setState(() => _sizeUnit = v ?? 'in'),
                ),
              ]),
              TextField(
                controller: _sizeCtrl,
                decoration: InputDecoration(
                    labelText: '目标尺寸 ($_sizeUnit)',
                    border: const OutlineInputBorder(),
                    isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _angleCtrl,
                decoration: InputDecoration(
                    labelText: '分划板读数 ($_unit)',
                    border: const OutlineInputBorder(),
                    isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      _distUnit == 'yd'
                          ? '${rangeYd.toStringAsFixed(0)} yd'
                          : '${rangeM.toStringAsFixed(0)} m',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('距离 · 约 ${(rangeM).toStringAsFixed(0)}m / ${(rangeYd).toStringAsFixed(0)}yd',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() =>
                              _distUnit = _distUnit == 'yd' ? 'm' : 'yd'),
                          child: Text('切换单位',
                              style: TextStyle(fontSize: 11, color: Colors.blue[700])),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('提示: 用目标的高度或宽度在分划板上数出 MIL/MOA 读数，'
                  '输入其真实尺寸即可估算距离。常用于已知尺寸目标（如 IPSC、靶板）。',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: rangeYd > 0
              ? () => Navigator.pop(context, rangeYd)
              : null,
          child: const Text('用作目标距离'),
        ),
      ],
    );
  }
}
