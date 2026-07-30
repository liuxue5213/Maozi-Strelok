import 'package:flutter/material.dart';

import '../models/firearm.dart';
import 'app_state.dart';
import 'modify_page.dart';
import 'compute_input_page.dart';

String _roleLabel(FirearmRole r) => switch (r) {
      FirearmRole.military => '军用',
      FirearmRole.police => '警用',
      FirearmRole.specialForces => '特种',
      FirearmRole.civilian => '民用',
      FirearmRole.competition => '竞技',
      FirearmRole.hunting => '狩猎',
    };

class FirearmDetailPage extends StatelessWidget {
  final AppState state;
  final Firearm firearm;
  const FirearmDetailPage({super.key, required this.state, required this.firearm});

  @override
  Widget build(BuildContext context) {
    final ct = state.db.defaultCartridge(firearm);
    final bullet = ct != null ? state.db.bullet(ct.bulletId) : null;
    return Scaffold(
      appBar: AppBar(title: Text(firearm.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('基本规格', [
            _row('厂商', firearm.manufacturer),
            _row('国家', firearm.country),
            _row('类别', firearm.category.name),
            _row('用途', firearm.roles.map(_roleLabel).join(', ')),
            _row('服役年份', '${firearm.yearIntroduced}'),
            _row('兼容口径', firearm.compatibleCalibers.join(', ')),
            _row('默认枪管长', '${firearm.barrelLengthIn}" '),
            _row('缠距', '1:${firearm.twistRateIn}" '),
            if (firearm.notes != null) _row('备注', firearm.notes!),
          ]),
          const SizedBox(height: 12),
          _section('默认弹药', [
            if (ct != null) ...[
              _row('型号', ct.designation),
              _row('厂商', ct.manufacturer),
              _row('初速', '${ct.muzzleVelocityFps.toStringAsFixed(0)} fps'),
              _row('参考枪管', '${ct.refBarrelLengthIn}"'),
            ],
            if (bullet != null) ...[
              _row('弹头', '${bullet.manufacturer} ${bullet.model}'),
              _row('弹重', '${bullet.massGr} gr'),
              _row('G1 BC', bullet.bcG1.toStringAsFixed(3)),
              if (bullet.bcG7 != null)
                _row('G7 BC', bullet.bcG7!.toStringAsFixed(3)),
            ],
          ]),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.build),
                  label: const Text('改装配置'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ModifyPage(state: state, firearm: firearm),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.calculate),
                  label: const Text('弹道计算'),
                  onPressed: () {
                    state.selectFirearm(firearm);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ComputeInputPage(state: state),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 90,
                child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
