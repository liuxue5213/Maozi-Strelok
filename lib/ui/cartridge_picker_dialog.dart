import 'package:flutter/material.dart';

import '../models/firearm.dart';
import 'app_state.dart';

/// Dialog to pick a cartridge. Lists cartridges compatible with the firearm's
/// calibers (or all if none match), with a search field.
class CartridgePickerDialog extends StatefulWidget {
  final AppState state;
  final Firearm firearm;
  const CartridgePickerDialog(
      {super.key, required this.state, required this.firearm});

  @override
  State<CartridgePickerDialog> createState() => _CartridgePickerDialogState();
}

class _CartridgePickerDialogState extends State<CartridgePickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final calibers = widget.firearm.compatibleCalibers.toSet();
    var list = widget.state.db.cartridges.where((c) {
      // Prefer matching the firearm's calibers; fall back to showing all on
      // empty query so the user can still pick anything.
      if (calibers.contains(c.caliber)) return true;
      return false;
    }).toList();
    if (list.isEmpty) list = widget.state.db.cartridges.toList();
    if (_q.isNotEmpty) {
      list = list
          .where((c) =>
              '${c.designation} ${c.manufacturer} ${c.caliber}'
                  .toLowerCase()
                  .contains(_q.toLowerCase()))
          .toList();
    }

    return AlertDialog(
      title: const Text('选择弹药'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索弹药/厂商/口径…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  final selected =
                      widget.state.cartridge?.id == c.id;
                  return ListTile(
                    leading: Icon(selected ? Icons.check_circle : Icons.label,
                        color: selected ? Colors.green : null),
                    title: Text(c.designation),
                    subtitle: Text(
                        '${c.manufacturer} · ${c.caliber} · ${c.muzzleVelocityFps.toStringAsFixed(0)} fps'),
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
      ],
    );
  }
}

/// Dialog to pick a bullet, optionally filtered by caliber.
class BulletPickerDialog extends StatefulWidget {
  final AppState state;
  final String? caliber;
  const BulletPickerDialog(
      {super.key, required this.state, this.caliber});

  @override
  State<BulletPickerDialog> createState() => _BulletPickerDialogState();
}

class _BulletPickerDialogState extends State<BulletPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    var list = widget.state.db.bullets.toList();
    if (widget.caliber != null &&
        widget.state.db.bullets.any((b) => b.caliber == widget.caliber)) {
      list = list.where((b) => b.caliber == widget.caliber).toList();
    }
    if (_q.isNotEmpty) {
      list = list
          .where((b) =>
              '${b.manufacturer} ${b.model} ${b.caliber}'
                  .toLowerCase()
                  .contains(_q.toLowerCase()))
          .toList();
    }

    return AlertDialog(
      title: const Text('选择弹头'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索弹头/厂商/口径…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final b = list[i];
                  final selected = widget.state.bullet?.id == b.id;
                  return ListTile(
                    leading: Icon(
                        selected ? Icons.check_circle : Icons.track_changes,
                        color: selected ? Colors.green : null),
                    title: Text('${b.manufacturer} ${b.model}'),
                    subtitle: Text(
                        '${b.massGr}gr · ${b.caliber} · G1 ${b.bcG1.toStringAsFixed(3)}'),
                    onTap: () => Navigator.pop(context, b),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
      ],
    );
  }
}
