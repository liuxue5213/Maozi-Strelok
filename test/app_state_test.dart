import 'package:flutter_test/flutter_test.dart';

import 'package:ballistics_calculator/physics/units.dart' as U;
import 'package:ballistics_calculator/services/database_service.dart';
import 'package:ballistics_calculator/ui/app_state.dart';

/// Round-trip coverage for AppState.toJson/fromJson — settings persistence
/// and profile snapshots both flow through this serialization, so a dropped
/// field here silently loses user data (this is how themeMode regressed once).
void main() {
  test('toJson/fromJson round-trips all user-adjustable fields', () {
    final db = DatabaseService();
    final s = AppState(db);

    // selections are id-based; leave them null, everything else populated
    s.temperatureC = -22.5;
    s.pressureHpa = 1042;
    s.relativeHumidity = 0.17;
    s.altitudeM = 3120;
    s.windSpeedMph = 12.5;
    s.windDirectionDeg = 37;
    s.windUnit = 'ms';
    s.windZones = const [
      WindZoneInput(fromYd: 0, toYd: 400, speedMph: 8, dirDeg: 270),
      WindZoneInput(fromYd: 400, toYd: 100000, speedMph: 15, dirDeg: 90),
    ];
    s.useZeroAtmo = true;
    s.zeroTempC = 8;
    s.zeroPressureHpa = 1001;
    s.zeroHumidity = 0.4;
    s.zeroAltitudeM = 250;
    s.scopeElevCorrection = 0.96;
    s.scopeWindCorrection = 1.04;
    s.latitudeDeg = 39.9;
    s.azimuthDeg = 315;
    s.useCoriolis = true;
    s.dragModelId = 'G7';
    s.maxRangeYd = 1500;
    s.stepYd = 25;
    s.useSpinDrift = false;
    s.losAngleDeg = -12;
    s.useAeroJump = true;
    s.targetSpeedMph = 8;
    s.chronoVelocityFps = 2610;
    s.powderTempF = 64;
    s.mvTempSensitivityFpsPerF = 1.8;
    s.cantAngleDeg = 5;
    s.clickMoa = 0.1;
    s.targetSizeIn = 18;
    s.gunAccuracyMoa = 0.6;
    s.shooterErrorMoa = 0.8;
    s.windErrorMph = 3.5;
    s.rangeErrorYd = 15;
    s.dsf = {300.0: 1.02, 600.0: 0.97, 900.0: 1.11};
    s.customTargetsYd = const [325, 640, 1010];
    s.unitSystem = U.UnitSystem.imperial;
    s.themeMode = 'dark';

    final restored = AppState(db)..fromJson(s.toJson(), db);

    expect(restored.temperatureC, s.temperatureC);
    expect(restored.pressureHpa, s.pressureHpa);
    expect(restored.relativeHumidity, s.relativeHumidity);
    expect(restored.altitudeM, s.altitudeM);
    expect(restored.windSpeedMph, s.windSpeedMph);
    expect(restored.windDirectionDeg, s.windDirectionDeg);
    expect(restored.windUnit, 'ms');
    expect(restored.windZones.length, 2);
    expect(restored.windZones[0].fromYd, 0);
    expect(restored.windZones[1].speedMph, 15);
    expect(restored.useZeroAtmo, isTrue);
    expect(restored.zeroTempC, 8);
    expect(restored.zeroPressureHpa, 1001);
    expect(restored.zeroHumidity, 0.4);
    expect(restored.zeroAltitudeM, 250);
    expect(restored.scopeElevCorrection, 0.96);
    expect(restored.scopeWindCorrection, 1.04);
    expect(restored.latitudeDeg, 39.9);
    expect(restored.azimuthDeg, 315);
    expect(restored.useCoriolis, isTrue);
    expect(restored.dragModelId, 'G7');
    expect(restored.maxRangeYd, 1500);
    expect(restored.stepYd, 25);
    expect(restored.useSpinDrift, isFalse);
    expect(restored.losAngleDeg, -12);
    expect(restored.useAeroJump, isTrue);
    expect(restored.targetSpeedMph, 8);
    expect(restored.chronoVelocityFps, 2610);
    expect(restored.powderTempF, 64);
    expect(restored.mvTempSensitivityFpsPerF, 1.8);
    expect(restored.cantAngleDeg, 5);
    expect(restored.clickMoa, 0.1);
    expect(restored.targetSizeIn, 18);
    expect(restored.gunAccuracyMoa, 0.6);
    expect(restored.shooterErrorMoa, 0.8);
    expect(restored.windErrorMph, 3.5);
    expect(restored.rangeErrorYd, 15);
    expect(restored.dsf[300.0], 1.02);
    expect(restored.dsf[900.0], 1.11);
    expect(restored.customTargetsYd, [325, 640, 1010]);
    expect(restored.unitSystem, U.UnitSystem.imperial);
    expect(restored.themeMode, 'dark');
  });

  test('fromJson with an empty/legacy map falls back to safe defaults', () {
    final db = DatabaseService();
    final s = AppState(db)..fromJson(const {}, db);

    expect(s.themeMode, 'system');
    expect(s.dragModelId, 'G1');
    expect(s.windUnit, 'mph');
    expect(s.temperatureC, 15);
    expect(s.pressureHpa, 1013.25);
    expect(s.unitSystem, U.UnitSystem.metric);
    expect(s.dsf, isEmpty);
    expect(s.windZones, isEmpty);
  });

  test('legacy useG7 boolean flag still resolves the drag model', () {
    final db = DatabaseService();
    final restored = AppState(db)
      ..fromJson(const {'useG7': true}, db);
    expect(restored.dragModelId, 'G7');
  });
}
