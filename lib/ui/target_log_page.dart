import 'package:flutter/material.dart';

import '../models/target_log.dart';
import '../physics/units.dart' as U;
import 'app_state.dart';

/// Target Log / shooting-session records. Mirrors Ballistic's "Target Log" —
/// records environmental conditions, point of impact, group size, and notes
/// for each session. Useful for tracking cold-barrel shots, load development,
/// and dope validation over time.
class TargetLogPage extends StatefulWidget {
  final AppState state;
  const TargetLogPage({super.key, required this.state});

  @override
  State<TargetLogPage> createState() => _TargetLogPageState();
}

class _TargetLogPageState extends State<TargetLogPage> {
  @override
  Widget build(BuildContext context) {
    final log = widget.state.db.targetLog;
    return Scaffold(
      appBar: AppBar(
        title: Text('目标日志 (${log.length})'),
        actions: [
          if (log.isNotEmpty)
            IconButton(
              tooltip: '清空日志',
              icon: const Icon(Icons.delete_forever),
              onPressed: () => _confirmClear(),
            ),
        ],
      ),
      body: log.isEmpty
          ? const Center(child: Text('暂无记录 — 点击 + 添加射击记录'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: log.length,
              itemBuilder: (ctx, i) => _entryCard(log[i]),
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加射击记录',
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _entryCard(TargetLogEntry e) {
    final db = widget.state.db;
    final f = db.firearm(e.firearmId);
    final b = db.bullet(e.bulletId);
    final name = f?.name ?? e.firearmId;
    final bullet = b != null ? '${b.massGr}gr ${b.model}' : e.bulletId;
    return Card(
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: e.coldBarrel ? Colors.blue : Colors.grey,
          child: Text('${e.rangeYd.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 10, color: Colors.white)),
        ),
        title: Text('$name · $bullet',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${_fmtDate(e.timestamp)}  ·  高低${e.dropIn >= 0 ? '+' : ''}${e.dropIn.toStringAsFixed(1)}"  '
            '风向${e.windageIn >= 0 ? '+' : ''}${e.windageIn.toStringAsFixed(1)}"  '
            '群组${e.groupSizeMoA > 0 ? '${e.groupSizeMoA.toStringAsFixed(1)}MOA' : '-'}',
            style: const TextStyle(fontSize: 11)),
        trailing: e.coldBarrel
            ? const Text('冷管', style: TextStyle(fontSize: 10, color: Colors.blue))
            : null,
        onTap: () => _showDetail(e),
      ),
    );
  }

  void _showDetail(TargetLogEntry e) {
    final db = widget.state.db;
    final f = db.firearm(e.firearmId);
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('${f?.name ?? e.firearmId} @ ${e.rangeYd.toStringAsFixed(0)}yd'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('时间', _fmtDate(e.timestamp)),
              _kv('弹药', '${db.bullet(e.bulletId)?.massGr ?? '-'}gr ${db.bullet(e.bulletId)?.model ?? '-'}'),
              _kv('高低', '${e.dropIn.toStringAsFixed(1)} in'),
              _kv('风向', '${e.windageIn.toStringAsFixed(1)} in'),
              _kv('群组', '${e.groupSizeMoA.toStringAsFixed(1)} MOA'),
              _kv('环境', '${e.temperatureC.toStringAsFixed(0)}°C / ${e.pressureHpa.toStringAsFixed(0)}hPa / 海拔${e.altitudeM.toStringAsFixed(0)}m'),
              _kv('风', '${e.windSpeedMph.toStringAsFixed(0)}mph @ ${e.windDirDeg.toStringAsFixed(0)}°'),
              if (e.notes != null && e.notes!.isNotEmpty) _kv('备注', e.notes!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('关闭'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              await widget.state.db.removeTargetLog(e.id);
              if (dctx.mounted) {
                Navigator.pop(dctx);
                if (mounted) setState(() {});
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 50, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey))),
            Text(v, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  String _fmtDate(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _addEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _TargetLogEditPage(state: widget.state)),
    ).then((_) => setState(() {}));
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('清空所有记录?'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await widget.state.db.clearTargetLog();
              if (dctx.mounted) {
                Navigator.pop(dctx);
                if (mounted) setState(() {});
              }
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

/// Entry form for a new shot record. Pre-fills environment from the current
/// AppState so the shooter only needs to enter impact + group size.
class _TargetLogEditPage extends StatefulWidget {
  final AppState state;
  const _TargetLogEditPage({required this.state});

  @override
  State<_TargetLogEditPage> createState() => _TargetLogEditPageState();
}

class _TargetLogEditPageState extends State<_TargetLogEditPage> {
  late String _firearmId;
  late String _cartridgeId;
  late String _bulletId;
  final _rangeCtrl = TextEditingController(text: '100');
  final _dropCtrl = TextEditingController(text: '0');
  final _windageCtrl = TextEditingController(text: '0');
  final _groupCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  bool _coldBarrel = false;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _firearmId = s.firearm?.id ?? (s.db.firearms.isNotEmpty ? s.db.firearms.first.id : '');
    _cartridgeId = s.cartridge?.id ?? (s.db.cartridges.isNotEmpty ? s.db.cartridges.first.id : '');
    _bulletId = s.bullet?.id ?? (s.db.bullets.isNotEmpty ? s.db.bullets.first.id : '');
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.state.db;
    final firearms = db.firearms;
    final bullets = db.bullets;
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加射击记录'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // firearm + bullet pickers
          DropdownButtonFormField<String>(
            value: _firearmId,
            decoration: const InputDecoration(labelText: '枪械', isDense: true),
            items: firearms
                .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                .toList(),
            onChanged: (v) => setState(() => _firearmId = v ?? _firearmId),
          ),
          DropdownButtonFormField<String>(
            value: _bulletId,
            decoration: const InputDecoration(labelText: '弹头', isDense: true),
            items: bullets.map((b) => DropdownMenuItem(
                value: b.id,
                child: Text('${b.manufacturer} ${b.model} ${b.massGr}gr'))).toList(),
            onChanged: (v) => setState(() => _bulletId = v ?? _bulletId),
          ),
          const SizedBox(height: 12),
          _tf(_rangeCtrl, '射程 (yd)'),
          _tf(_dropCtrl, '实测高低 (in, +高/-低)'),
          _tf(_windageCtrl, '实测风向 (in, +右/-左)'),
          _tf(_groupCtrl, '群组 (MOA)'),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: '备注', isDense: true),
            maxLines: 3,
          ),
          CheckboxListTile(
            dense: true,
            title: const Text('冷枪管首发'),
            value: _coldBarrel,
            onChanged: (v) => setState(() => _coldBarrel = v ?? false),
          ),
          const Divider(),
          // environment (pre-filled from current state)
          Text('环境 (自动填充自当前计算设置)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              '${s.temperatureC.toStringAsFixed(1)}°C  ${s.pressureHpa.toStringAsFixed(1)}hPa  '
              '湿度${(s.relativeHumidity * 100).toStringAsFixed(0)}%  海拔${s.altitudeM.toStringAsFixed(0)}m  '
              '风${s.windSpeedMph.toStringAsFixed(1)}mph@${s.windDirectionDeg.toStringAsFixed(0)}°',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存记录'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  void _save() async {
    final s = widget.state;
    final entry = TargetLogEntry.create(
      firearmId: _firearmId,
      cartridgeId: s.cartridge?.id ?? '',
      bulletId: _bulletId,
      temperatureC: s.temperatureC,
      pressureHpa: s.pressureHpa,
      humidity: s.relativeHumidity,
      altitudeM: s.altitudeM,
      windSpeedMph: s.windSpeedMph,
      windDirDeg: s.windDirectionDeg,
      rangeYd: double.tryParse(_rangeCtrl.text) ?? 100,
      dropIn: double.tryParse(_dropCtrl.text) ?? 0,
      windageIn: double.tryParse(_windageCtrl.text) ?? 0,
      groupSizeMoA: double.tryParse(_groupCtrl.text) ?? 0,
      coldBarrel: _coldBarrel,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.state.db.addTargetLog(entry);
    if (mounted) Navigator.pop(context);
  }
}
