import 'package:flutter/material.dart';

import '../models/firearm.dart';
import 'app_state.dart';

/// Editor for user-defined custom records (bullets, cartridges, firearms).
///
/// A tabbed form: pick the kind of record, fill in the fields, save. Saved
/// records get a "user-" id prefix and persist via DatabaseService, then appear
/// alongside built-ins in the pickers/lists.
class EditCustomPage extends StatelessWidget {
  final AppState state;
  const EditCustomPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('自定义数据'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.track_changes), text: '弹头'),
            Tab(icon: Icon(Icons.inventory_2), text: '弹药'),
            Tab(icon: Icon(Icons.gps_fixed), text: '枪械'),
          ]),
        ),
        body: TabBarView(
          children: [
            _BulletEditor(state: state),
            _CartridgeEditor(state: state),
            _FirearmEditor(state: state),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bullet editor
// ---------------------------------------------------------------------------
class _BulletEditor extends StatefulWidget {
  final AppState state;
  const _BulletEditor({required this.state});

  @override
  State<_BulletEditor> createState() => _BulletEditorState();
}

class _BulletEditorState extends State<_BulletEditor> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _manu = TextEditingController();
  final _model = TextEditingController();
  final _caliber = TextEditingController();
  final _mass = TextEditingController(text: '150');
  final _dia = TextEditingController(text: '0.308');
  final _len = TextEditingController(text: '1.2');
  final _bcG1 = TextEditingController(text: '0.400');
  final _bcG7 = TextEditingController();
  BulletType _type = BulletType.bthp;

  @override
  void dispose() {
    for (final c in [_id, _manu, _model, _caliber, _mass, _dia, _len, _bcG1, _bcG7]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(_id, 'ID (唯一标识，如 my-168smk)'),
          _tf(_manu, '厂商'),
          _tf(_model, '型号'),
          _tf(_caliber, '口径 (如 .308 Win)'),
          _num(_mass, '弹重 (grain)'),
          _num(_dia, '直径 (inch)'),
          _num(_len, '长度 (inch)'),
          _num(_bcG1, 'G1 弹道系数'),
          _tf(_bcG7, 'G7 弹道系数 (可选)'),
          DropdownButtonFormField<BulletType>(
            value: _type,
            decoration: const InputDecoration(labelText: '弹头类型'),
            items: BulletType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? BulletType.bthp),
          ),
          const SizedBox(height: 16),
          // list existing custom bullets
          _existingList(
            title: '已保存的自定义弹头',
            items: widget.state.db.bullets
                .where((b) => b.id.startsWith('user-'))
                .toList(),
            titleOf: (b) => '${b.manufacturer} ${b.model}',
            subtitleOf: (b) => '${b.massGr}gr · G1 ${b.bcG1}',
            onDelete: (b) async {
              await widget.state.db.removeBullet(b.id);
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存弹头'),
            onPressed: () => _save(),
          ),
        ],
      ),
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    final b = Bullet(
      id: _id.text.trim().isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : _id.text.trim(),
      manufacturer: _manu.text,
      model: _model.text,
      caliber: _caliber.text,
      massGr: double.parse(_mass.text),
      diameterIn: double.parse(_dia.text),
      lengthIn: double.parse(_len.text),
      bcG1: double.parse(_bcG1.text),
      bcG7: _bcG7.text.trim().isEmpty ? null : double.tryParse(_bcG7.text),
      type: _type,
    );
    await widget.state.db.addBullet(b);
    if (!mounted) return;
    setState(() {});
    _clear();
    _snack('弹头已保存');
  }

  void _clear() {
    for (final c in [_id, _manu, _model, _caliber, _bcG7]) {
      c.clear();
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _tf(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          validator: (v) => (v == null || double.tryParse(v) == null)
              ? '请输入有效数字'
              : null,
        ),
      );
}

// ---------------------------------------------------------------------------
// Cartridge editor
// ---------------------------------------------------------------------------
class _CartridgeEditor extends StatefulWidget {
  final AppState state;
  const _CartridgeEditor({required this.state});

  @override
  State<_CartridgeEditor> createState() => _CartridgeEditorState();
}

class _CartridgeEditorState extends State<_CartridgeEditor> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _des = TextEditingController();
  final _manu = TextEditingController();
  final _caliber = TextEditingController();
  final _mv = TextEditingController(text: '2700');
  final _barrel = TextEditingController(text: '20');
  final _notes = TextEditingController();
  String? _bulletId;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(_id, 'ID (唯一)'),
          _tf(_des, '型号名称 (如 M118LR)'),
          _tf(_manu, '厂商'),
          _tf(_caliber, '口径'),
          _num(_mv, '初速 (fps)'),
          _num(_barrel, '参考枪管长 (inch)'),
          DropdownButtonFormField<String>(
            value: _bulletId,
            decoration: const InputDecoration(labelText: '使用弹头'),
            items: widget.state.db.bullets
                .map((b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(
                          '${b.manufacturer} ${b.model} (${b.massGr}gr)'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _bulletId = v),
          ),
          _tf(_notes, '备注 (可选)'),
          const SizedBox(height: 16),
          _existingList(
            title: '已保存的自定义弹药',
            items: widget.state.db.cartridges
                .where((c) => c.id.startsWith('user-'))
                .toList(),
            titleOf: (c) => c.designation,
            subtitleOf: (c) =>
                '${c.manufacturer} · ${c.muzzleVelocityFps.toStringAsFixed(0)} fps',
            onDelete: (c) async {
              await widget.state.db.removeCartridge(c.id);
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存弹药'),
            onPressed: () => _save(),
          ),
        ],
      ),
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    final c = Cartridge(
      id: _id.text.trim().isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : _id.text.trim(),
      designation: _des.text,
      manufacturer: _manu.text,
      caliber: _caliber.text,
      muzzleVelocityFps: double.parse(_mv.text),
      refBarrelLengthIn: double.parse(_barrel.text),
      bulletId: _bulletId ?? widget.state.db.bullets.first.id,
      notes: _notes.text.trim().isEmpty ? null : _notes.text,
    );
    await widget.state.db.addCartridge(c);
    if (!mounted) return;
    setState(() {});
    for (final x in [_id, _des, _manu, _caliber, _notes]) {
      x.clear();
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('弹药已保存')));
  }

  Widget _tf(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          validator: (v) =>
              (v == null || double.tryParse(v) == null) ? '请输入有效数字' : null,
        ),
      );
}

// ---------------------------------------------------------------------------
// Firearm editor
// ---------------------------------------------------------------------------
class _FirearmEditor extends StatefulWidget {
  final AppState state;
  const _FirearmEditor({required this.state});

  @override
  State<_FirearmEditor> createState() => _FirearmEditorState();
}

class _FirearmEditorState extends State<_FirearmEditor> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _manu = TextEditingController();
  final _country = TextEditingController();
  final _calibers = TextEditingController();
  final _barrel = TextEditingController(text: '20');
  final _twist = TextEditingController(text: '10');
  final _sight = TextEditingController(text: '1.6');
  final _year = TextEditingController(text: '2020');
  final _notes = TextEditingController();
  FirearmCategory _category = FirearmCategory.boltRifle;
  Set<FirearmRole> _roles = {FirearmRole.civilian};
  String? _defaultCartridgeId;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(_id, 'ID (唯一)'),
          _tf(_name, '名称'),
          _tf(_manu, '厂商'),
          _tf(_country, '国家'),
          _tf(_calibers, '兼容口径 (逗号分隔，如 .308 Win,7.62 NATO)'),
          _num(_barrel, '默认枪管长 (inch)'),
          _num(_twist, '缠距 (inch/turn)'),
          _num(_sight, '默认瞄具高度 (inch)'),
          _num(_year, '服役年份'),
          DropdownButtonFormField<FirearmCategory>(
            value: _category,
            decoration: const InputDecoration(labelText: '类别'),
            items: FirearmCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? FirearmCategory.boltRifle),
          ),
          const SizedBox(height: 8),
          Wrap(
            children: FirearmRole.values.map((r) {
              return FilterChip(
                label: Text(r.name),
                selected: _roles.contains(r),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _roles.add(r);
                  } else {
                    _roles.remove(r);
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _defaultCartridgeId,
            decoration: const InputDecoration(labelText: '默认弹药'),
            items: widget.state.db.cartridges
                .map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.designation} (${c.caliber})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _defaultCartridgeId = v),
          ),
          _tf(_notes, '备注 (可选)'),
          const SizedBox(height: 16),
          _existingList(
            title: '已保存的自定义枪械',
            items: widget.state.db.firearms
                .where((f) => f.id.startsWith('user-'))
                .toList(),
            titleOf: (f) => f.name,
            subtitleOf: (f) => '${f.manufacturer} · ${f.country}',
            onDelete: (f) async {
              await widget.state.db.removeFirearm(f.id);
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存枪械'),
            onPressed: () => _save(),
          ),
        ],
      ),
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    final f = Firearm(
      id: _id.text.trim().isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : _id.text.trim(),
      name: _name.text,
      manufacturer: _manu.text,
      country: _country.text,
      category: _category,
      roles: _roles.toList(),
      compatibleCalibers: _calibers.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      barrelLengthIn: double.parse(_barrel.text),
      twistRateIn: double.parse(_twist.text),
      sightHeightIn: double.parse(_sight.text),
      defaultCartridgeId: _defaultCartridgeId ??
          (widget.state.db.cartridges.isNotEmpty
              ? widget.state.db.cartridges.first.id
              : ''),
      yearIntroduced: int.tryParse(_year.text) ?? 2020,
      notes: _notes.text.trim().isEmpty ? null : _notes.text,
    );
    await widget.state.db.addFirearm(f);
    if (!mounted) return;
    setState(() {});
    for (final x in [_id, _name, _manu, _country, _calibers, _notes]) {
      x.clear();
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('枪械已保存')));
  }

  Widget _tf(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) =>
              (v == null || double.tryParse(v) == null) ? '请输入有效数字' : null,
        ),
      );
}

// ---------------------------------------------------------------------------
// Shared existing-records list with delete
// ---------------------------------------------------------------------------
Widget _existingList<T>({
  required String title,
  required List<T> items,
  required String Function(T) titleOf,
  required String Function(T) subtitleOf,
  required Future<void> Function(T) onDelete,
}) {
  if (items.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title, style: const TextStyle(color: Colors.grey)),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ...items.map((t) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(titleOf(t)),
            subtitle: Text(subtitleOf(t)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => onDelete(t),
            ),
          )),
    ],
  );
}
