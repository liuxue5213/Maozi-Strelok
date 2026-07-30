import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/units.dart' as U;
import 'package:ballistics_calculator/physics/atmosphere.dart';
import 'package:ballistics_calculator/physics/drag_models.dart';
import 'package:ballistics_calculator/physics/ballistics_solver.dart';

/// Helpers to build a shot from imperial input values (the units shooters use).
ShotConfig imperialShot({
  required double v0fps,
  required double bc,
  required double massGr,
  required double diaIn,
  required double sightHeightIn,
  required double zeroYd,
  required double maxRangeYd,
  DragModel? drag,
}) {
  final mass = U.Units.grainToKg(massGr);
  final diameter = U.Units.inchToM(diaIn);
  final sightHeight = U.Units.inchToM(sightHeightIn);
  final zero = U.Units.yardsToM(zeroYd);
  return ShotConfig(
    muzzleVelocity: U.Units.fpsToMps(v0fps),
    mass: mass,
    diameter: diameter,
    bc: bc,
    dragModel: drag ?? G1DragModel.instance,
    sightHeight: sightHeight,
    zeroRange: zero,
    atmosphere: Atmosphere.standardIcao(),
    wind: const Wind.calm(),
  );
}

void main() {
  group('BallisticsSolver — zero crossing', () {
    test('drop is ~0 at the zero range (168gr .308 SMK)', () {
      // 168gr Sierra MatchKing, G1 BC=0.462, MV=2600fps, zero 200yd.
      final cfg = imperialShot(
        v0fps: 2600,
        bc: 0.462,
        massGr: 168,
        diaIn: 0.308,
        sightHeightIn: 1.5,
        zeroYd: 200,
        maxRangeYd: 1000,
      );
      final s = BallisticsSolver(cfg);
      final traj = s.solve(maxRangeM: U.Units.yardsToM(600), stepM: U.Units.yardsToM(100));
      // find the point closest to the 200yd zero
      final zeroPt = traj.reduce((a, b) =>
          (a.range - U.Units.yardsToM(200)).abs() <
                  (b.range - U.Units.yardsToM(200)).abs()
              ? a
              : b);
      // Should be within ~3 cm of the LOS at the zero range.
      expect(zeroPt.drop.abs(), lessThan(0.03));
    });
  });

  group('BallisticsSolver — known drop values (168gr .308 SMK @ 2600fps)', () {
    // Reference values (JBM / Hornady, 200yd zero, 1.5" sight height, G1 0.462):
    //   300yd drop ~ -6.0" (-15cm)
    //   500yd drop ~ -45"  (-114cm)
    //   remaining velocity @500yd ~ 1600 fps (~488 m/s)
    // We allow generous tolerance because published tables vary slightly by
    // drag-function source and zero convention.
    late List<TrajectoryPoint> traj;
    setUp(() {
      final cfg = imperialShot(
        v0fps: 2600,
        bc: 0.462,
        massGr: 168,
        diaIn: 0.308,
        sightHeightIn: 1.5,
        zeroYd: 200,
        maxRangeYd: 1000,
      );
      traj = BallisticsSolver(cfg)
          .solve(maxRangeM: U.Units.yardsToM(600), stepM: U.Units.yardsToM(50));
    });

    TrajectoryPoint atYd(double yd) {
      final m = U.Units.yardsToM(yd);
      return traj.reduce((a, b) =>
          (a.range - m).abs() < (b.range - m).abs() ? a : b);
    }

    test('300yd drop ~ -20cm', () {
      final p = atYd(300);
      // published ~ -7.8in (-19.8cm); within +/- 4 cm
      expect(p.drop, closeTo(-0.198, 0.04));
    });

    test('500yd drop ~ -108cm', () {
      final p = atYd(500);
      // published ~ -42in (-107cm); within +/- 10 cm
      expect(p.drop, closeTo(-1.077, 0.10));
    });

    test('500yd remaining velocity ~ 678 m/s (2224 fps)', () {
      final p = atYd(500);
      expect(p.speed, closeTo(678, 35));
    });

    test('muzzle speed preserved at range 0', () {
      final p = atYd(0);
      expect(p.speed, closeTo(U.Units.fpsToMps(2600), 5));
    });
  });

  group('BallisticsSolver — wind drift', () {
    test('crosswind produces rightward drift for 270deg (from-left) wind', () {
      final base = imperialShot(
        v0fps: 2600,
        bc: 0.462,
        massGr: 168,
        diaIn: 0.308,
        sightHeightIn: 1.5,
        zeroYd: 200,
        maxRangeYd: 1000,
      );
      // 10 mph from the left (270deg) at 100yd -> a few inches right.
      final cfg = ShotConfig(
        muzzleVelocity: base.muzzleVelocity,
        mass: base.mass,
        diameter: base.diameter,
        bc: base.bc,
        dragModel: base.dragModel,
        sightHeight: base.sightHeight,
        zeroRange: base.zeroRange,
        atmosphere: base.atmosphere,
        wind: Wind(speedMs: U.Units.mphToMps(10), directionDeg: 270),
      );
      final traj =
          BallisticsSolver(cfg).solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      // Drift grows with range and is positive (to the right) at every sample >0.
      for (final p in traj) {
        if (p.range > 1) {
          expect(p.windage, greaterThan(0));
        }
      }
      // At 400yd with a 10mph crosswind, ~10-25 inches (0.25-0.6 m) is typical.
      final at400 = traj.reduce((a, b) =>
          (a.range - U.Units.yardsToM(400)).abs() < (b.range - U.Units.yardsToM(400)).abs()
              ? a
              : b);
      expect(at400.windage, greaterThan(0.2));
      expect(at400.windage, lessThan(0.8));
    });

    test('calm wind -> no drift', () {
      final cfg = imperialShot(
        v0fps: 2600,
        bc: 0.462,
        massGr: 168,
        diaIn: 0.308,
        sightHeightIn: 1.5,
        zeroYd: 200,
        maxRangeYd: 1000,
      );
      final traj =
          BallisticsSolver(cfg).solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      for (final p in traj) {
        expect(p.windage.abs(), lessThan(1e-3));
      }
    });
  });

  group('BallisticsSolver — energy decreases monotonically', () {
    test('energy falls with range', () {
      final cfg = imperialShot(
        v0fps: 2600,
        bc: 0.462,
        massGr: 168,
        diaIn: 0.308,
        sightHeightIn: 1.5,
        zeroYd: 200,
        maxRangeYd: 1000,
      );
      final traj =
          BallisticsSolver(cfg).solve(maxRangeM: U.Units.yardsToM(800), stepM: U.Units.yardsToM(100));
      for (int i = 1; i < traj.length; i++) {
        expect(traj[i].energy, lessThanOrEqualTo(traj[i - 1].energy + 1));
      }
      // muzzle energy for 168gr @ 2600fps ~ 2518 ft-lbf ~ 3415 J
      expect(traj.first.energy, closeTo(3415, 100));
    });
  });
}
