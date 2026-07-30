import 'package:flutter/foundation.dart';

import '../models/firearm.dart';
import '../models/modification.dart';
import '../physics/units.dart' as U;
import '../services/database_service.dart';

/// Central app state: selected firearm/cartridge/bullet, modification,
/// environment, wind, unit system, and computation parameters.
///
/// All user-adjustable settings are persisted to SharedPreferences so they
/// survive app restarts. Selection of a new firearm preserves the user's
/// previously-chosen modification where it still applies.
class AppState extends ChangeNotifier {
  final DatabaseService db;

  AppState(this.db);

  // --- Selections ---
  Firearm? _firearm;
  Cartridge? _cartridge;
  Bullet? _bullet;
  Modification _mod = const Modification();

  // --- Environment (SI) ---
  double temperatureC = 15;
  double pressureHpa = 1013.25;
  double relativeHumidity = 0.5;
  double altitudeM = 0;

  // --- Wind (imperial input, converted) ---
  double windSpeedMph = 0;
  double windDirectionDeg = 270; // default: from left

  // --- Shooting params ---
  double latitudeDeg = 0;
  double azimuthDeg = 0; // bearing CW from North
  bool useCoriolis = false;
  bool useG7 = false;
  double maxRangeYd = 800;
  double stepYd = 100;
  bool useSpinDrift = true;
  double losAngleDeg = 0; // line-of-sight elevation, +uphill

  U.UnitSystem unitSystem = U.UnitSystem.metric;

  Firearm? get firearm => _firearm;
  Cartridge? get cartridge => _cartridge;
  Bullet? get bullet => _bullet;
  Modification get mod => _mod;

  /// Load persisted settings. Call once at startup.
  Future<void> loadSettings() async {
    await db.loadSettingsInto(this);
  }

  /// Persist all settings. Called after mutations.
  Future<void> _persist() async {
    await db.saveSettingsFrom(this);
  }

  /// Select a firearm. Preserves the user's zero range / muzzle device, but
  /// adopts the firearm's default barrel, twist and sight height (since those
  /// are firearm-specific). Auto-selects its default cartridge.
  void selectFirearm(Firearm f) {
    _firearm = f;
    // Carry over user-chosen zero and muzzle device; reset firearm-specific
    // geometric params to the new platform's defaults.
    _mod = Modification(
      sightHeightIn: f.sightHeightIn,
      zeroRangeYd: _mod.zeroRangeYd,
      muzzleDevice: _mod.muzzleDevice,
    );
    final ct = db.defaultCartridge(f);
    if (ct != null) selectCartridge(ct, persist: false);
    _persist();
    notifyListeners();
  }

  /// Select a cartridge (and its bullet) by id, e.g. when restoring state.
  void selectCartridgeById(String id) {
    final ct = db.cartridge(id);
    if (ct != null) selectCartridge(ct);
  }

  void selectFirearmById(String id) {
    final f = db.firearm(id);
    if (f != null) selectFirearm(f);
  }

  /// Select a cartridge and resolve its bullet.
  void selectCartridge(Cartridge c, {bool persist = true}) {
    _cartridge = c;
    final b = db.bullet(c.bulletId);
    if (b != null) _bullet = b;
    if (persist) {
      _persist();
      notifyListeners();
    }
  }

  /// Switch to a different bullet (manual override) — useful when the user
  /// hand-loads with a custom projectile. Does not change the cartridge.
  void selectBullet(Bullet b) {
    _bullet = b;
    _persist();
    notifyListeners();
  }

  void updateMod(Modification m) {
    _mod = m;
    _persist();
    notifyListeners();
  }

  void toggleUnitSystem() {
    unitSystem = unitSystem == U.UnitSystem.metric
        ? U.UnitSystem.imperial
        : U.UnitSystem.metric;
    _persist();
    notifyListeners();
  }

  void setEnvironment({
    double? temperatureC,
    double? pressureHpa,
    double? relativeHumidity,
    double? altitudeM,
  }) {
    if (temperatureC != null) this.temperatureC = temperatureC;
    if (pressureHpa != null) this.pressureHpa = pressureHpa;
    if (relativeHumidity != null) this.relativeHumidity = relativeHumidity;
    if (altitudeM != null) this.altitudeM = altitudeM;
  }

  // Environment & shooting params are mutated directly by the UI via setState;
  // call this to persist after edits.
  Future<void> persistEnvAndShooting() => _persist();

  bool get canCompute => _firearm != null && _cartridge != null && _bullet != null;

  /// Reset to a clean default state (used by "new search" flows).
  void clearSelection() {
    _firearm = null;
    _cartridge = null;
    _bullet = null;
    notifyListeners();
  }

  // ---- Serialization for persistence ----
  Map<String, dynamic> toJson() => {
        'firearmId': _firearm?.id,
        'cartridgeId': _cartridge?.id,
        'bulletId': _bullet?.id,
        'mod': _mod.toJson(),
        'temperatureC': temperatureC,
        'pressureHpa': pressureHpa,
        'relativeHumidity': relativeHumidity,
        'altitudeM': altitudeM,
        'windSpeedMph': windSpeedMph,
        'windDirectionDeg': windDirectionDeg,
        'latitudeDeg': latitudeDeg,
        'azimuthDeg': azimuthDeg,
        'useCoriolis': useCoriolis,
        'useG7': useG7,
        'maxRangeYd': maxRangeYd,
        'stepYd': stepYd,
        'useSpinDrift': useSpinDrift,
        'losAngleDeg': losAngleDeg,
        'unitSystem': unitSystem.name,
      };

  void fromJson(Map<String, dynamic> m, DatabaseService db) {
    temperatureC = (m['temperatureC'] as num?)?.toDouble() ?? 15;
    pressureHpa = (m['pressureHpa'] as num?)?.toDouble() ?? 1013.25;
    relativeHumidity = (m['relativeHumidity'] as num?)?.toDouble() ?? 0.5;
    altitudeM = (m['altitudeM'] as num?)?.toDouble() ?? 0;
    windSpeedMph = (m['windSpeedMph'] as num?)?.toDouble() ?? 0;
    windDirectionDeg = (m['windDirectionDeg'] as num?)?.toDouble() ?? 270;
    latitudeDeg = (m['latitudeDeg'] as num?)?.toDouble() ?? 0;
    azimuthDeg = (m['azimuthDeg'] as num?)?.toDouble() ?? 0;
    useCoriolis = (m['useCoriolis'] as bool?) ?? false;
    useG7 = (m['useG7'] as bool?) ?? false;
    maxRangeYd = (m['maxRangeYd'] as num?)?.toDouble() ?? 800;
    stepYd = (m['stepYd'] as num?)?.toDouble() ?? 100;
    useSpinDrift = (m['useSpinDrift'] as bool?) ?? true;
    losAngleDeg = (m['losAngleDeg'] as num?)?.toDouble() ?? 0;
    unitSystem = U.UnitSystem.values
        .byName((m['unitSystem'] as String?) ?? 'metric');
    _mod = m['mod'] is Map
        ? Modification.fromJson(m['mod'] as Map<String, dynamic>)
        : const Modification();
    final fid = m['firearmId'] as String?;
    if (fid != null) {
      final f = db.firearm(fid);
      if (f != null) {
        _firearm = f;
        // restore sight height from mod (keep persisted mod)
      }
    }
    final cid = m['cartridgeId'] as String?;
    if (cid != null) {
      _cartridge = db.cartridge(cid);
    }
    final bid = m['bulletId'] as String?;
    if (bid != null) {
      _bullet = db.bullet(bid);
    }
  }
}
