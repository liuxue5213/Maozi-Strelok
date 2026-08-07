import 'package:flutter/material.dart';

import '../models/firearm.dart';
import '../services/database_service.dart';
import 'app_state.dart';
import 'barrel_life_page.dart';
import 'dsf_page.dart';
import 'edit_custom_page.dart';
import 'firearm_detail_page.dart';
import 'my_gear_page.dart';
import 'profile_page.dart';
import 'target_log_page.dart';
import 'truing_page.dart';

/// Browsing page: category chips, search, list of firearms.
class HomePage extends StatefulWidget {
  final AppState state;
  const HomePage({super.key, required this.state});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = '';
  FirearmCategory? _category;
  FirearmRole? _role;
  bool _favoritesOnly = false;

  DatabaseService get db => widget.state.db;

  @override
  Widget build(BuildContext context) {
    final list = db.firearms.where((f) {
      if (_favoritesOnly && !widget.state.db.isFavorite(f.id)) return false;
      if (_category != null && f.category != _category) return false;
      if (_role != null && !f.roles.contains(_role)) return false;
      if (_query.isNotEmpty &&
          !('${f.name} ${f.manufacturer} ${f.country} ${f.compatibleCalibers.join(' ')}'
              .toLowerCase()
              .contains(_query.toLowerCase()))) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ballistics Calculator'),
        actions: [
          IconButton(
            tooltip: '我的装备 (快速载入常用配置)',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MyGearPage(state: widget.state),
                ),
              );
              setState(() {});
            },
          ),
          IconButton(
            tooltip: '配置文件 (Profiles)',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfilePage(state: widget.state),
                ),
              );
              setState(() {});
            },
          ),
          IconButton(
            tooltip: '目标日志',
            icon: const Icon(Icons.fact_check),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TargetLogPage(state: widget.state),
                ),
              );
              setState(() {});
            },
          ),
          IconButton(
            tooltip: '弹道校准 (Truing)',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TruingPage(state: widget.state),
                ),
              );
              setState(() {});
            },
          ),
          IconButton(
            tooltip: '多点落点校准 (DSF)',
            icon: const Icon(Icons.stacked_line_chart),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DsfPage(state: widget.state),
                ),
              );
              setState(() {});
            },
          ),
          IconButton(
            tooltip: '枪管寿命追踪',
            icon: const Icon(Icons.history),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BarrelLifePage(state: widget.state),
                ),
              );
              setState(() {});
            },
          ),
          IconButton(
            tooltip: '自定义数据',
            icon: const Icon(Icons.playlist_add),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditCustomPage(state: widget.state),
                ),
              );
              setState(() {});
            },
          ),
          IconButton(
            tooltip: '单位切换',
            icon: Icon(widget.state.unitSystem.name == 'metric'
                ? Icons.straighten
                : Icons.square_foot),
            onPressed: widget.state.toggleUnitSystem,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索枪械/厂商/国家/口径…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _chip('收藏', _favoritesOnly, () => setState(
                    () => _favoritesOnly = !_favoritesOnly), Icons.star),
                ...FirearmCategory.values.map((c) => _chip(
                    _categoryLabel(c), _category == c, () => setState(() {
                      _category = _category == c ? null : c;
                    }), null)),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: FirearmRole.values
                  .map((r) => _chip(_roleLabel(r), _role == r, () => setState(() {
                        _role = _role == r ? null : r;
                      }), null))
                  .toList(),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('无匹配结果'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final f = list[i];
                      final fav = db.isFavorite(f.id);
                      return ListTile(
                        leading: CircleAvatar(child: Text('${f.yearIntroduced}')),
                        title: Text(f.name),
                        subtitle: Text(
                          '${f.manufacturer} · ${f.country} · ${f.compatibleCalibers.join(', ')}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(fav ? Icons.star : Icons.star_border,
                                  color: fav ? Colors.amber : null),
                              onPressed: () {
                                db.toggleFavorite(f.id);
                                setState(() {});
                              },
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FirearmDetailPage(state: widget.state, firearm: f),
                            ),
                          );
                          setState(() {});
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, IconData? icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: icon != null ? Icon(icon, size: 16) : null,
      ),
    );
  }

  String _categoryLabel(FirearmCategory c) => switch (c) {
        FirearmCategory.pistol => '手枪',
        FirearmCategory.assaultRifle => '突击步枪',
        FirearmCategory.battleRifle => '战斗步枪',
        FirearmCategory.sniper => '狙击步枪',
        FirearmCategory.dmr => '精确射手',
        FirearmCategory.machineGun => '通用机枪',
        FirearmCategory.heavyMG => '重机枪',
        FirearmCategory.smg => '冲锋枪',
        FirearmCategory.pdw => 'PDW',
        FirearmCategory.shotgun => '霰弹枪',
        FirearmCategory.boltRifle => '栓动步枪',
        FirearmCategory.antiMaterial => '反器材',
      };

  String _roleLabel(FirearmRole r) => switch (r) {
        FirearmRole.military => '军用',
        FirearmRole.police => '警用',
        FirearmRole.specialForces => '特种',
        FirearmRole.civilian => '民用',
        FirearmRole.competition => '竞技',
        FirearmRole.hunting => '狩猎',
      };
}
