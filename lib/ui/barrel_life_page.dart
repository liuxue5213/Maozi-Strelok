import 'package:flutter/material.dart';

import '../models/firearm.dart';
import 'app_state.dart';

/// Barrel-life tracking page. Per-firearm round count, expected-life progress,
/// and cleaning-interval tracking. Mirrors dedicated apps like Barrel Burner.
class BarrelLifePage extends StatefulWidget {
  final AppState state;
  const BarrelLifePage({super.key, required this.state});

  @override
  State<BarrelLifePage> createState() => _BarrelLifePageState();
}

class _BarrelLifePageState extends State<BarrelLifePage> {
  @override
  Widget build(BuildContext context) {
    final db = widget.state.db;
    final firearms = db.firearms;
    return Scaffold(
      appBar: AppBar(title: const Text('枪管寿命追踪')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('枪管寿命追踪'),
              subtitle: Text('记录每支枪的射击次数、预估寿命和清洁间隔。'
                  '枪管磨损会逐步降低精度，建议在寿命临近时更换。'),
            ),
          ),
          const SizedBox(height: 12),
          ...firearms.map((f) => _firearmCard(f)),
        ],
      ),
    );
  }

  Widget _firearmCard(Firearm f) {
    final db = widget.state.db;
    final rounds = db.roundsFor(f.id);
    final life = db.expectedLife(f.id);
    final sinceClean = db.roundsSinceClean(f.id);
    final pct = life > 0 ? (rounds / life).clamp(0.0, 1.0) : 0.0;
    final remaining = (life - rounds).clamp(0, life);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(f.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.settings, size: 20),
                  onSelected: (v) async {
                    if (v == 'clean') {
                      await db.markCleaned(f.id);
                      setState(() {});
                    } else if (v == 'setlife') {
                      _setLifeDialog(f);
                    } else if (v == 'reset') {
                      await db.addRounds(f.id, -rounds);
                      setState(() {});
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'clean', child: Text('已清洁')),
                    PopupMenuItem(value: 'setlife', child: Text('设置预期寿命')),
                    PopupMenuItem(value: 'reset', child: Text('重置计数')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('$rounds / $life 发  ·  剩余 $remaining 发',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              color: _pctColor(pct),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _statChip('上次清洁后', '$sinceClean 发',
                      sinceClean > 200 ? Colors.orange : Colors.grey),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statChip('磨损', '${(pct * 100).toStringAsFixed(0)}%',
                      _pctColor(pct)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('+10 发'),
                    onPressed: () async {
                      await db.addRounds(f.id, 10);
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_circle, size: 18),
                    label: const Text('+50 发'),
                    onPressed: () async {
                      await db.addRounds(f.id, 50);
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.cleaning_services, size: 18),
                    label: const Text('已清洁'),
                    onPressed: () async {
                      await db.markCleaned(f.id);
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            if (pct > 0.9)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('⚠ 枪管寿命临近，建议尽快更换',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        ],
      ),
    );
  }

  Color _pctColor(double p) {
    if (p > 0.9) return Colors.red;
    if (p > 0.7) return Colors.orange;
    return Colors.green;
  }

  void _setLifeDialog(Firearm f) {
    final ctrl = TextEditingController(text: widget.state.db.expectedLife(f.id).toString());
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('${f.name} 预期寿命'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: '预期总射击次数', suffixText: '发'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final v = int.tryParse(ctrl.text);
              if (v != null && v > 0) {
                await widget.state.db.setExpectedLife(f.id, v);
                if (dctx.mounted) {
                  Navigator.pop(dctx);
                  setState(() {});
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
