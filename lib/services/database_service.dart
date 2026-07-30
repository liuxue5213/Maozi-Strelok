import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firearm.dart';

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

  final List<Bullet> _bullets = [];
  final List<Cartridge> _cartridges = [];
  final List<Firearm> _firearms = [];
  final Set<String> _favorites = {};

  List<Bullet> get bullets => List.unmodifiable(_bullets);
  List<Cartridge> get cartridges => List.unmodifiable(_cartridges);
  List<Firearm> get firearms => List.unmodifiable(_firearms);
  bool get isLoaded => _firearms.isNotEmpty;

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

    final prefs = await SharedPreferences.getInstance();
    _bullets.addAll(_loadUser<Bullet>(prefs, _kBullets, Bullet.fromJson));
    _cartridges
        .addAll(_loadUser<Cartridge>(prefs, _kCartridges, Cartridge.fromJson));
    _firearms
        .addAll(_loadUser<Firearm>(prefs, _kFirearms, Firearm.fromJson));
    _favorites
      ..clear()
      ..addAll(prefs.getStringList(_kFavorites) ?? const []);
  }

  // ---- App settings persistence (selections, environment, units) ----
  static const _kSettings = 'app_settings';

  Future<void> loadSettingsInto(state) async {
    final prefs = await SharedPreferences.getInstance();
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
