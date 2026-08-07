import 'package:flutter/material.dart';

import '../models/reticle.dart';
import 'reticle_painter.dart';
import 'app_state.dart';

/// Reticle library picker: browse / search the real-scope reticle library,
/// filter by manufacturer, and preview each reticle live before selecting it.
/// Mirrors Strelok's reticle-library picker.
class ReticlePickerDialog extends StatefulWidget {
  final AppState state;
  /// Currently selected reticle id (for highlighting).
  final String? currentId;
  const ReticlePickerDialog({super.key, required this.state, this.currentId});

  @override
  State<ReticlePickerDialog> createState() => _ReticlePickerDialogState();
}

class _ReticlePickerDialogState extends State<ReticlePickerDialog> {
  String _query = '';
  String? _mfrFilter;

  @override
  Widget build(BuildContext context) {
    final all = widget.state.db.reticles;
    final manufacturers =
        (all.map((r) => r.manufacturer).toSet().toList()..sort());
    var filtered = all.where((r) {
      if (_mfrFilter != null && r.manufacturer != _mfrFilter) return false;
      if (_query.isNotEmpty &&
          !'${r.name} ${r.manufacturer} ${r.unit}'
              .toLowerCase()
              .contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Dialog(
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('分划板库',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索分划板 / 厂商…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  FilterChip(
                    label: const Text('全部'),
                    selected: _mfrFilter == null,
                    onSelected: (_) => setState(() => _mfrFilter = null),
                  ),
                  const SizedBox(width: 4),
                  ...manufacturers.map((m) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(m),
                          selected: _mfrFilter == m,
                          onSelected: (_) => setState(
                              () => _mfrFilter = _mfrFilter == m ? null : m),
                        ),
                      )),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('无匹配分划板'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final r = filtered[i];
                        final selected = r.id == widget.currentId;
                        return _reticleTile(r, selected);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reticleTile(ReticleSpec r, bool selected) {
    return InkWell(
      onTap: () => Navigator.pop(context, r),
      borderRadius: BorderRadius.circular(8),
      child: Card(
        color: selected ? Colors.green.withValues(alpha: 0.12) : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: ReticleLibraryPainter(
                        spec: r,
                        elevUnits: 0,
                        windUnits: 0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
              Text('${r.manufacturer} · ${r.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
