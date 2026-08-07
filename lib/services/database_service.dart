import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firearm.dart';
import '../models/reticle.dart';

/// Loads built-in data from assets and merges user-defined (custom) records
/// stored in SharedPreferences. Provides unified query APIs.
///
/// Custom records share the schema of their built-in counterparts; a custom
/// record id is prefixed with "user-" so it never collides with built-ins.
class DatabaseService {
  static const _kBullets = 'user_bullets';
  static const _kCartridges = 'user_cartridges';
  static const _kFirearms = 'user_firearms';
  static const _kFavorites = 'user_favorites';
  static const _kBarrelLife = 'barrel_life';

  final List<Bullet> _bullets = [];
  final List<Cartridge> _cartridges = [];
  final List<Firearm> _firearms = [];
  final List<ReticleSpec> _reticles = [];
  final Set<String> _favorites = {};
  /// Per-firearm barrel-life tracking: firearmId -> {rounds, lastCleanRounds, expectedLife}.
  final Map<String, Map<String, int>> _barrelLife = {};

  List<Bullet> get bullets => List.unmodifiable(_bullets);
  List<Cartridge> get cartridges => List.unmodifiable(_cartridges);
  List<Firearm> get firearms => List.unmodifiable(_firearms);
  List<ReticleSpec> get reticles => List.unmodifiable(_reticles);
  bool get isLoaded => _firearms.isNotEmpty;

  /// Look up a reticle by id.
  ReticleSpec? reticle(String id) =>
      _reticles.where((r) => r.id == id).firstOrNull;

  /// Load built-in + user data. Call once at app start.
  Future<void> load() async {
    final bJson = await rootBundle.loadString('assets/data/bullets.json');
    final cJson = await rootBundle.loadString('assets/data/cartridges.json');
    final fJson = await rootBundle.loadString('assets/data/firearms.json');
    _bullets
      ..clear()
      ..addAll((jsonDecode(bJson) as List)
          .map((e) => Bullet.fromJson(e as Map<String, dynamic>)));
    _cartridges
      ..clear()
      ..addAll((jsonDecode(cJson) as List)
          .map((e) => Cartridge.fromJson(e as Map<String, dynamic>)));
    _firearms
      ..clear()
      ..addAll((jsonDecode(fJson) as List)
          .map((e) => Firearm.fromJson(e as Map<String, dynamic>)));
    // Reticle library (real-world scope reticles).
    final rJson = await rootBundle.loadString('assets/data/reticles.json');
    _reticles
      ..clear()
      ..addAll((jsonDecode(rJson) as List)
          .map((e) => ReticleSpec.fromJson(e as Map<String, dynamic>)));

    final prefs = await SharedPreferences.getInstance();
    _bullets.addAll(_loadUser<Bullet>(prefs, _kBullets, Bullet.fromJson));
    _cartridges
        .addAll(_loadUser<Cartridge>(prefs, _kCartridges, Cartridge.fromJson));
    _firearms
        .addAll(_loadUser<Firearm>(prefs, _kFirearms, Firearm.fromJson));
    _favorites
      ..clear()
      ..addAll(prefs.getStringList(_kFavorites) ?? const []);
    _barrelLife
      ..clear()
      ..addAll(_loadBarrelLife(prefs));
  }

  // ---- Barrel-life tracking ----
  Map<String, Map<String, int>> _loadBarrelLife(SharedPreferences prefs) {
    final raw = prefs.getString(_kBarrelLife);
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(
        k, (v as Map).map((kk, vv) => MapEntry(kk as String, (vv as num).toInt()))));
  }

  Future<void> _saveBarrelLife() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBarrelLife, jsonEncode(_barrelLife));
  }

  /// Rounds fired through [firearmId]. 0 if untracked.
  int roundsFor(String firearmId) => _barrelLife[firearmId]?['rounds'] ?? 0;

  /// Rounds since last cleaning for [firearmId].
  int roundsSinceClean(String firearmId) =>
      roundsFor(firearmId) - (_barrelLife[firearmId]?['lastCleanRounds'] ?? 0);

  /// Expected barrel life (rounds) for [firearmId].
  int expectedLife(String firearmId) =>
      _barrelLife[firearmId]?['expectedLife'] ?? 3000;

  /// Record [n] more rounds through [firearmId].
  Future<void> addRounds(String firearmId, int n) async {
    final rec = Map<String, int>.from(_barrelLife[firearmId] ?? {});
    rec['rounds'] = (rec['rounds'] ?? 0) + n;
    rec['lastCleanRounds'] ??= 0;
    rec['expectedLife'] ??= _defaultLife(firearmId);
    _barrelLife[firearmId] = rec;
    await _saveBarrelLife();
  }

  /// Set the expected barrel life (rounds) for [firearmId].
  Future<void> setExpectedLife(String firearmId, int life) async {
    final rec = Map<String, int>.from(_barrelLife[firearmId] ?? {});
    rec['rounds'] ??= 0;
    rec['lastCleanRounds'] ??= 0;
    rec['expectedLife'] = life;
    _barrelLife[firearmId] = rec;
    await _saveBarrelLife();
  }

  /// Mark the barrel as cleaned now (resets the since-clean counter).
  Future<void> markCleaned(String firearmId) async {
    final rec = Map<String, int>.from(_barrelLife[firearmId] ?? {});
    rec['rounds'] ??= 0;
    rec['lastCleanRounds'] = rec['rounds']!;
    rec['expectedLife'] ??= _defaultLife(firearmId);
    _barrelLife[firearmId] = rec;
    await _saveBarrelLife();
  }

  /// Default expected life by caliber (rough industry rules of thumb).
  int _defaultLife(String firearmId) {
    final f = firearm(firearmId);
    if (f == null) return 3000;
    final c = f.compatibleCalibers.join(' ').toLowerCase();
    if (c.contains('.50') || c.contains('12.7')) return 5000;
    if (c.contains('.300') || c.contains('7.62') || c.contains('.308')) return 4000;
    if (c.contains('5.56') || c.contains('.223') || c.contains('5.45')) return 8000;
    if (c.contains('6.5') || c.contains('6.8')) return 2500;
    if (c.contains('9') || c.contains('.45') || c.contains('9x18')) return 20000;
    return 3000;
  }

  /// All tracked firearm ids.
  Iterable<String> get trackedBarrels => _barrelLife.keys;

  // ---- App settings persistence (selections, environment, units) ----
  static const _kSettings = 'app_settings';

  // ---- Profiles persistence (named full gun+ammo+env combos) ----
  static const _kProfiles = 'saved_profiles';

  /// Save the current full configuration as a named profile.
  Future<void> saveProfile(String name, Map<String, dynamic> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = _allProfiles(prefs);
    profiles[name] = snapshot;
    await prefs.setString(_kProfiles, jsonEncode(profiles));
  }

  Future<void> deleteProfile(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = _allProfiles(prefs);
    profiles.remove(name);
    await prefs.setString(_kProfiles, jsonEncode(profiles));
  }

  Map<String, Map<String, dynamic>> loadProfiles() {
    // synchronous wrapper using a cached read; prefs are loaded once at startup
    return _profilesCache;
  }

  Map<String, Map<String, dynamic>> _profilesCache = {};
  Future<void> refreshProfilesCache() async {
    final prefs = await SharedPreferences.getInstance();
    _profilesCache = _allProfiles(prefs);
  }

  Map<String, Map<String, dynamic>> _allProfiles(SharedPreferences prefs) {
    final raw = prefs.getString(_kProfiles);
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, v as Map<String, dynamic>));
  }

  Future<void> loadSettingsInto(state) async {
    final prefs = await SharedPreferences.getInstance();
    await refreshProfilesCache();
    final raw = prefs.getString(_kSettings);
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    state.fromJson(m, this);
  }

  Future<void> saveSettingsFrom(state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettings, jsonEncode(state.toJson()));
  }

  List<T> _loadUser<T>(
    SharedPreferences prefs,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveUser<T>(
    SharedPreferences prefs,
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) async {
    await prefs.setString(
        key, jsonEncode(items.map(toJson).toList()));
  }

  // ---- Lookups ----
  Bullet? bullet(String id) =>
      _bullets.where((b) => b.id == id).firstOrNull;
  Cartridge? cartridge(String id) =>
      _cartridges.where((c) => c.id == id).firstOrNull;
  Firearm? firearm(String id) =>
      _firearms.where((f) => f.id == id).firstOrNull;

  /// Cartridges compatible with a given caliber.
  List<Cartridge> cartridgesForCaliber(String caliber) =>
      _cartridges.where((c) => c.caliber == caliber).toList();

  /// The bullet used by a cartridge.
  Bullet? bulletForCartridge(Cartridge c) => bullet(c.bulletId);

  /// Default cartridge + bullet for a firearm.
  Cartridge? defaultCartridge(Firearm f) => cartridge(f.defaultCartridgeId);

  // ---- Favorites ----
  bool isFavorite(String firearmId) => _favorites.contains(firearmId);
  Future<void> toggleFavorite(String firearmId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_favorites.add(firearmId)) _favorites.remove(firearmId);
    await prefs.setStringList(_kFavorites, _favorites.toList());
  }

  // ---- Custom record management (CRUD) ----
  Future<void> addBullet(Bullet b) async {
    final prefs = await SharedPreferences.getInstance();
    final userOnly = [
      ..._bullets.where((e) => e.id.startsWith('user-') && e.id != 'user-${b.id}'),
      b.copyWithId('user-${b.id}'),
    ];
    await _saveUser(prefs, _kBullets, userOnly, (x) => x.toJson());
    await load();
  }

  Future<void> addCartridge(Cartridge c) async {
    final prefs = await SharedPreferences.getInstance();
    final userOnly = [
      ..._cartridges.where((e) => e.id.startsWith('user-') && e.id != 'user-${c.id}'),
      c.copyWithId('user-${c.id}'),
    ];
    await _saveUser(prefs, _kCartridges, userOnly, (x) => x.toJson());
    await load();
  }

  Future<void> addFirearm(Firearm f) async {
    final prefs = await SharedPreferences.getInstance();
    final userOnly = [
      ..._firearms.where((e) => e.id.startsWith('user-') && e.id != 'user-${f.id}'),
      f.copyWithId('user-${f.id}'),
    ];
    await _saveUser(prefs, _kFirearms, userOnly, (x) => x.toJson());
    await load();
  }

  Future<void> removeBullet(String id) =>
      _remove(_kBullets, id, (p) => load());
  Future<void> removeCartridge(String id) =>
      _remove(_kCartridges, id, (p) => load());
  Future<void> removeFirearm(String id) =>
      _remove(_kFirearms, id, (p) => load());

  Future<void> _remove(String key, String id, Future<void> Function(SharedPreferences) reload) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .map((e) => e as Map<String, dynamic>)
        .where((e) => e['id'] != id && e['id'] != 'user-$id')
        .toList();
    await prefs.setString(key, jsonEncode(list));
    await reload(prefs);
  }
}

/// copyWithId helpers on data models (kept here to avoid cluttering models).
extension BulletCopy on Bullet {
  Bullet copyWithId(String newId) => Bullet(
        id: newId,
        manufacturer: manufacturer,
        model: model,
        caliber: caliber,
        massGr: massGr,
        diameterIn: diameterIn,
        lengthIn: lengthIn,
        bcG1: bcG1,
        bcG7: bcG7,
        type: type,
      );
}

extension CartridgeCopy on Cartridge {
  Cartridge copyWithId(String newId) => Cartridge(
        id: newId,
        designation: designation,
        manufacturer: manufacturer,
        caliber: caliber,
        muzzleVelocityFps: muzzleVelocityFps,
        refBarrelLengthIn: refBarrelLengthIn,
        bulletId: bulletId,
        notes: notes,
      );
}

extension FirearmCopy on Firearm {
  Firearm copyWithId(String newId) => Firearm(
        id: newId,
        name: name,
        manufacturer: manufacturer,
        country: country,
        category: category,
        roles: roles,
        compatibleCalibers: compatibleCalibers,
        barrelLengthIn: barrelLengthIn,
        twistRateIn: twistRateIn,
        sightHeightIn: sightHeightIn,
        defaultCartridgeId: defaultCartridgeId,
        yearIntroduced: yearIntroduced,
        notes: notes,
      );
}
