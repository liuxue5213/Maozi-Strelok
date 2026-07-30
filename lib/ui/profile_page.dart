import 'package:flutter/material.dart';

import 'app_state.dart';

/// Profile management page: save the entire current configuration (gun + ammo
/// + bullet + mods + environment + wind + shooting params) under a name, and
/// restore it later. Mirrors Applied Ballistics' profile feature.
class ProfilePage extends StatefulWidget {
  final AppState state;
  const ProfilePage({super.key, required this.state});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
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
      appBar: AppBar(title: const Text('配置文件 (Profiles)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.bookmark_add),
              title: const Text('保存当前配置'),
              subtitle: Text(_currentSummary(s)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _saveDialog(s),
            ),
          ),
          const SizedBox(height: 16),
          const Text('已保存的配置文件',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(),
          if (profiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('尚无保存的配置文件',
                      style: TextStyle(color: Colors.grey))),
            ),
          ...profiles.entries.map((e) {
            final name = e.key;
            final m = e.value;
            return ListTile(
              leading: const Icon(Icons.bookmark, color: Colors.green),
              title: Text(name),
              subtitle: Text(_profileSummary(m)),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'load') {
                    await s.loadProfile(name);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已加载配置: $name')));
                      setState(() {});
                    }
                  } else if (v == 'delete') {
                    await s.deleteProfile(name);
                    setState(() {});
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'load', child: Text('加载此配置')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _currentSummary(AppState s) {
    return '${s.firearm?.name ?? '-'} · ${s.cartridge?.designation ?? '-'} · '
        '${s.bullet?.model ?? '-'}';
  }

  String _profileSummary(Map<String, dynamic> m) {
    final f = m['firearmId'] ?? '-';
    final c = m['cartridgeId'] ?? '-';
    final zr = m['mod'] is Map ? (m['mod']['zeroRangeYd'] ?? '-') : '-';
    return '$f · $c · 归零${zr}yd';
  }

  void _saveDialog(AppState s) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('保存配置文件'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '配置名称 (如: 我的.308远程配置)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              await s.saveProfile(name);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已保存配置: $name')));
                setState(() {});
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
