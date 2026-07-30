import 'package:flutter/foundation.dart';

import '../models/firearm.dart';
import '../models/modification.dart';
import '../physics/units.dart' as U;
import '../services/database_service.dart';

/// Central app state: selected firearm/cartridge/bullet, modification,
/// environment, wind, unit system, and computation parameters.
///
/// Exposes [compute] to build the solver inputs and run the trajectory.
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

  U.UnitSystem unitSystem = U.UnitSystem.metric;

  Firearm? get firearm => _firearm;
  Cartridge? get cartridge => _cartridge;
  Bullet? get bullet => _bullet;
  Modification get mod => _mod;

  void selectFirearm(Firearm f) {
    _firearm = f;
    final ct = db.defaultCartridge(f);
    if (ct != null) selectCartridge(ct);
    // reset sight height to firearm default
    _mod = Modification(
      sightHeightIn: f.sightHeightIn,
      zeroRangeYd: 100,
    );
    notifyListeners();
  }

  void selectCartridge(Cartridge c) {
    _cartridge = c;
    final b = db.bullet(c.bulletId);
    if (b != null) _bullet = b;
    notifyListeners();
  }

  void selectBullet(Bullet b) {
    _bullet = b;
    notifyListeners();
  }

  void updateMod(Modification m) {
    _mod = m;
    notifyListeners();
  }

  void toggleUnitSystem() {
    unitSystem = unitSystem == U.UnitSystem.metric
        ? U.UnitSystem.imperial
        : U.UnitSystem.metric;
    notifyListeners();
  }

  bool get canCompute => _firearm != null && _cartridge != null && _bullet != null;
}
