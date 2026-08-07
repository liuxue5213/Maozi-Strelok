import 'package:flutter/material.dart';

import 'app_state.dart';
import 'compute_input_page.dart';

/// 我的装备 (My Gear) — quick access to your saved gun/ammo/scope combos.
///
/// Each saved profile (gun + ammo + bullet + mods + environment) is shown as a
/// gear card; one tap loads it and jumps straight into the compute page, so a
/// frequently-used rifle is reachable in one tap instead of re-selecting every
/// time. Mirrors the "favorites / rifle profiles" quick-switch of Ballistic.
class MyGearPage extends StatefulWidget {
  final AppState state;
  const MyGearPage({super.key, required this.state});

  @override
  State<MyGearPage> createState() => _MyGearPageState();
}

class _MyGearPageState extends State<MyGearPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.state.db.refreshProfilesCache();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final profiles = s.profiles;
    return Scaffold(
      appBar: AppBar(title: const Text('我的装备')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('我的装备'),
              subtitle: Text('把常用的枪械+弹药+瞄具组合保存为装备，'
                  '点一下即可载入并进入弹道计算。保存请使用右上角的"配置文件"。'),
            ),
          ),
          const SizedBox(height: 8),
          if (profiles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无装备 — 去"配置文件"保存一套即可')),
            )
          else
            ...profiles.entries.map((e) => _gearCard(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _gearCard(String name, Map<String, dynamic> snap) {
    final s = widget.state;
    final fId = snap['firearmId'] as String?;
    final cId = snap['cartridgeId'] as String?;
    final firearm = fId != null ? s.db.firearm(fId) : null;
    final cart = cId != null ? s.db.cartridge(cId) : null;
    final mod = snap['mod'] is Map
        ? (snap['mod'] as Map)
        : null;
    final zero = mod?['zeroRangeYd']?.toString() ?? '-';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 18, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                IconButton(
                  tooltip: '删除装备',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _delete(name),
                ),
              ],
            ),
            Text(
                '${firearm?.name ?? '?'}  ·  ${cart?.designation ?? '?'}'
                '  ·  归零 ${zero}yd',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('载入并计算'),
                    onPressed: () => _load(name),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('载入'),
                    onPressed: () => _load(name, gotoCompute: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _load(String name, {bool gotoCompute = true}) async {
    final s = widget.state;
    await s.loadProfile(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已载入装备: $name')));
    if (gotoCompute && s.canCompute) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ComputeInputPage(state: s)),
      );
    } else {
      setState(() {});
    }
  }

  Future<void> _delete(String name) async {
    final s = widget.state;
    await s.deleteProfile(name);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已删除: $name')));
  }
}
