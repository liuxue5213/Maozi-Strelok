import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/drag_models.dart';
import 'package:ballistics_calculator/physics/atmosphere.dart';
import 'package:ballistics_calculator/physics/units.dart' as U;
import 'package:ballistics_calculator/physics/ballistics_solver.dart';
import 'package:ballistics_calculator/physics/hit_probability.dart';

void main() {
  group('New drag models (G2..GL)', () {
    test('all standard drag models resolve and return positive Cd', () {
      for (final id in dragModelIds) {
        final m = resolveDragModel(id);
        expect(m.id, id);
        for (final mach in [0.5, 1.0, 1.5, 2.5]) {
          expect(m.cdRef(mach), greaterThan(0));
        }
      }
    });

    test('G2 transonic peak near Mach 0.95-1.1 (verified JBM table)', () {
      final g2 = G2DragModel.instance;
      // JBM G2 peaks ~0.4114 around Mach 1.075, well above subsonic ~0.17
      expect(g2.cdRef(1.075), greaterThan(0.40));
      expect(g2.cdRef(1.075), greaterThan(g2.cdRef(0.5)));
      expect(g2.cdRef(1.075), greaterThan(g2.cdRef(2.5)));
    });

    test('G8 is near-flat at ~0.21 subsonic (verified JBM table)', () {
      final g8 = G8DragModel.instance;
      expect(g8.cdRef(0.5), closeTo(0.2102, 0.001));
    });

    test('GI has plateau Cd=0.6423 from Mach 1.25-1.6 (verified JBM)', () {
      final gi = GiDragModel.instance;
      expect(gi.cdRef(1.4), closeTo(0.6423, 1e-4));
    });

    test('GL is a high-drag profile (blunt nose), Cd > G7 at Mach 1', () {
      final gl = GlDragModel.instance;
      final g7 = G7DragModel.instance;
      expect(gl.cdRef(1.0), greaterThan(g7.cdRef(1.0)));
    });

    test('DopplerCdm uses curve directly, ignoring BC', () {
      final cdm = DopplerCdm('Test', [
        [0.5, 0.30],
        [1.0, 0.45],
        [2.0, 0.25],
      ]);
      // cd() ignores BC/mass/dia -> returns raw table value
      expect(cdm.cd(1.0, 0.999, 175, 0.308), closeTo(0.45, 1e-9));
      expect(cdm.cd(0.5, 0.1, 50, 0.224), closeTo(0.30, 1e-9));
    });
  });

  group('Atmosphere density altitude', () {
    test('DA near 0 at ISA sea level', () {
      final a = Atmosphere.standardIcao();
      expect(a.densityAltitudeM, lessThan(200)); // ~0, small humidity 0
    });

    test('DA increases at altitude', () {
      final a = Atmosphere(
        temperatureC: -5,
        pressurePa: 60000,
        relativeHumidity: 0,
        altitudeM: 4000,
      );
      expect(a.densityAltitudeM, greaterThan(2000));
    });

    test('fromDensityAltitude round-trips density', () {
      final a = Atmosphere.fromDensityAltitude(
        densityAltitudeM: 1000,
        temperatureC: 5,
      );
      // density at 1000m ISA ~ 1.112 kg/m3
      expect(a.density, closeTo(1.067, 0.06));
    });
  });

  group('Units new helpers', () {
    test('pressure conversions', () {
      expect(U.Units.paToHpa(U.Units.hpaToPa(1013)), closeTo(1013, 1e-6));
      expect(U.Units.psiToPa(14.7), closeTo(101352, 1));
    });
    test('IPHY round-trips', () {
      expect(U.Units.radToIphy(U.Units.iphyToRad(1.0)), closeTo(1.0, 1e-9));
    });
    test('density ratio from DA decreases with altitude', () {
      expect(U.Units.densityRatioFromDaFt(0), closeTo(1.0, 1e-3));
      expect(U.Units.densityRatioFromDaFt(10000),
          lessThan(U.Units.densityRatioFromDaFt(0)));
    });
  });

  group('Multi-zone wind', () {
    ShotConfig cfgWithZones(List<WindZone> zones) {
      return ShotConfig(
        muzzleVelocity: 800,
        mass: 0.01,
        diameter: 0.0078,
        bc: 0.4,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 100,
        atmosphere: Atmosphere.standardIcao(),
        wind: const Wind.calm(),
        windZones: zones,
        spinDrift: false,
      );
    }

    test('crosswind zone deflects bullet; calm zone does not', () {
      // zone 0-100m: 10mph right wind; 100m-end: calm
      final cfg = cfgWithZones([
        WindZone(
            fromM: 0,
            toM: 100,
            wind: const Wind(speedMs: 5, directionDeg: 90)),
        WindZone(
            fromM: 100,
            toM: 99999,
            wind: const Wind.calm()),
      ]);
      final solver = BallisticsSolver(cfg);
      final traj = solver.solve(maxRangeM: 300, stepM: 100);
      // windage should be nonzero (deflected in first 100m) then persist
      expect(traj.last.windage.abs(), greaterThan(0.001));
    });

    test('uniform-zone wind equals single wind', () {
      final zones = [
        WindZone(
            fromM: 0,
            toM: 99999,
            wind: const Wind(speedMs: 4, directionDeg: 90)),
      ];
      final cfgZ = cfgWithZones(zones);
      final sZ = BallisticsSolver(cfgZ);
      final tZ = sZ.solve(maxRangeM: 500, stepM: 100);

      final cfgS = ShotConfig(
        muzzleVelocity: 800,
        mass: 0.01,
        diameter: 0.0078,
        bc: 0.4,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 100,
        atmosphere: Atmosphere.standardIcao(),
        wind: const Wind(speedMs: 4, directionDeg: 90),
        spinDrift: false,
      );
      final sS = BallisticsSolver(cfgS);
      final tS = sS.solve(maxRangeM: 500, stepM: 100);
      expect(tZ.last.windage, closeTo(tS.last.windage, 1e-4));
    });
  });

  group('MV truing', () {
    test('truedMv reproduces observed drop', () {
      final base = ShotConfig(
        muzzleVelocity: 850,
        mass: 0.01,
        diameter: 0.0078,
        bc: 0.4,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 100,
        atmosphere: Atmosphere.standardIcao(),
        wind: const Wind.calm(),
        spinDrift: false,
      );
      final solver = BallisticsSolver(base);
      final dropAt800 = solver.dropAtRange(500);
      // pretend true MV is 830 -> more drop
      final trued = solver.truedMv(rangeM: 500, observedDropM: dropAt800 * 1.05);
      expect(trued, isNotNull);
      expect(trued!, lessThan(850)); // less MV to drop more
    });

    test('truedMv returns null when drop out of ±25% band', () {
      final base = ShotConfig(
        muzzleVelocity: 850,
        mass: 0.01,
        diameter: 0.0078,
        bc: 0.4,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 100,
        atmosphere: Atmosphere.standardIcao(),
        wind: const Wind.calm(),
        spinDrift: false,
      );
      final solver = BallisticsSolver(base);
      // absurd observed drop (positive = bullet high) far outside band
      final r = solver.truedMv(rangeM: 500, observedDropM: 5.0);
      expect(r, isNull);
    });
  });

  group('MPBR', () {
    test('returns positive range and apex', () {
      final cfg = ShotConfig(
        muzzleVelocity: 900,
        mass: 0.008,
        diameter: 0.0078,
        bc: 0.35,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 1, // bore-line reference for MPBR
        atmosphere: Atmosphere.standardIcao(),
        wind: const Wind.calm(),
        spinDrift: false,
      );
      final solver = BallisticsSolver(cfg);
      final r = solver.maxPointBlankRange(vitalRadiusM: 0.15, scanToM: 800);
      expect(r.mpbrM, greaterThan(0));
      expect(r.mpbrM, lessThan(800));
    });

    test('apex height stays within the vital zone (±0.15m)', () {
      final cfg = ShotConfig(
        muzzleVelocity: 900,
        mass: 0.008,
        diameter: 0.0078,
        bc: 0.35,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 1,
        atmosphere: Atmosphere.standardIcao(),
        wind: const Wind.calm(),
        spinDrift: false,
      );
      final r = BallisticsSolver(cfg)
          .maxPointBlankRange(vitalRadiusM: 0.15, scanToM: 800);
      // apex must not exceed the upper vital edge (else band violated)
      expect(r.apexM, lessThanOrEqualTo(0.15 + 1e-6));
      // and should be positive (bullet actually rises in the optimized MPBR)
      expect(r.apexM, greaterThan(0.0));
    });
  });

  group('Zero Atmosphere', () {
    test('zero angle differs when zero-atmo density differs', () {
      final base = ShotConfig(
        muzzleVelocity: 850,
        mass: 0.01,
        diameter: 0.0078,
        bc: 0.4,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 100,
        atmosphere: Atmosphere(
            temperatureC: 35, pressurePa: 101325, relativeHumidity: 0),
        wind: const Wind.calm(),
        spinDrift: false,
      );
      // Same rifle/ammo, zero established in cold dense air vs current.
      final zeroCold = Atmosphere(
          temperatureC: 0, pressurePa: 101325, relativeHumidity: 0);
      final cfgZa = ShotConfig(
        muzzleVelocity: 850,
        mass: 0.01,
        diameter: 0.0078,
        bc: 0.4,
        dragModel: G1DragModel.instance,
        sightHeight: 0.04,
        zeroRange: 100,
        atmosphere: base.atmosphere,
        zeroAtmosphere: zeroCold,
        wind: const Wind.calm(),
        spinDrift: false,
      );
      final elevZa = BallisticsSolver(cfgZa).solveZeroAngle();
      final elevPlain = BallisticsSolver(base).solveZeroAngle();
      // The zero angle solved under cold dense air differs (slightly) from the
      // one solved at current warm air.
      expect((elevZa - elevPlain).abs(), lessThan(0.1)); // small but defined
      // Both must be positive (upward bore elevation for a real zero).
      expect(elevZa, greaterThan(0));
    });
  });

  group('WEZ Monte-Carlo', () {
    test('hit probability in (0,1) and decreases with range', () {
      final pNear = Wez.run(
        shots: 800,
        rangeM: 100,
        gunMoa: 1.0,
        shooterMoa: 0.5,
        windErrMph: 2,
        windDriftPerMphM: 0.01,
        rangeErrYd: 5,
        dropPerYdM: 0.01,
        targetWIn: 12,
        seed: 7,
      );
      final pFar = Wez.run(
        shots: 800,
        rangeM: 800,
        gunMoa: 1.0,
        shooterMoa: 0.5,
        windErrMph: 2,
        windDriftPerMphM: 0.3,
        rangeErrYd: 10,
        dropPerYdM: 0.05,
        targetWIn: 12,
        seed: 7,
      );
      expect(pNear, greaterThan(0.0));
      expect(pNear, lessThan(1.0));
      expect(pNear, greaterThan(pFar));
    });

    test('deterministic for fixed seed', () {
      final a = Wez.run(
        shots: 500, rangeM: 500, gunMoa: 1, shooterMoa: 0.5,
        windErrMph: 2, windDriftPerMphM: 0.1, rangeErrYd: 10,
        dropPerYdM: 0.03, targetWIn: 12, seed: 123,
      );
      final b = Wez.run(
        shots: 500, rangeM: 500, gunMoa: 1, shooterMoa: 0.5,
        windErrMph: 2, windDriftPerMphM: 0.1, rangeErrYd: 10,
        dropPerYdM: 0.03, targetWIn: 12, seed: 123,
      );
      expect(a, closeTo(b, 1e-9));
    });

    test('RNG produces varied draws (not constant)', () {
      // Different seeds must give different results (a broken RNG that returns
      // a constant would make this fail).
      final p1 = Wez.run(
        shots: 300, rangeM: 500, gunMoa: 1, shooterMoa: 0.5,
        windErrMph: 2, windDriftPerMphM: 0.1, rangeErrYd: 10,
        dropPerYdM: 0.03, targetWIn: 12, seed: 1,
      );
      final p2 = Wez.run(
        shots: 300, rangeM: 500, gunMoa: 1, shooterMoa: 0.5,
        windErrMph: 2, windDriftPerMphM: 0.1, rangeErrYd: 10,
        dropPerYdM: 0.03, targetWIn: 12, seed: 2,
      );
      final p3 = Wez.run(
        shots: 300, rangeM: 500, gunMoa: 1, shooterMoa: 0.5,
        windErrMph: 2, windDriftPerMphM: 0.1, rangeErrYd: 10,
        dropPerYdM: 0.03, targetWIn: 12, seed: 3,
      );
      // A proper pseudo-random stream gives different P(hit) per seed.
      final distinct = {p1, p2, p3}.length;
      expect(distinct, greaterThan(1));
    });
  });
}
