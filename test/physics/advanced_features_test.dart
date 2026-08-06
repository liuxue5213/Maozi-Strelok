import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/units.dart' as U;
import 'package:ballistics_calculator/physics/atmosphere.dart';
import 'package:ballistics_calculator/physics/drag_models.dart';
import 'package:ballistics_calculator/physics/ballistics_solver.dart';

/// Tests for advanced engine features: spin drift, angle fire, truing, and the
/// new zero/maxRange helpers. Independent of solver_extras_test.dart.
void main() {
  // A standard .308 175gr load for all scenarios.
  ShotConfig baseConfig({
    bool spinDrift = false,
    double losAngleDeg = 0,
    double cantAngleRad = 0,
    double? bcOverride,
    double twistIn = 12,
    double lengthIn = 1.26,
  }) =>
      ShotConfig(
        muzzleVelocity: U.Units.fpsToMps(2600),
        mass: U.Units.grainToKg(175),
        diameter: U.Units.inchToM(0.308),
        bc: bcOverride ?? 0.505,
        dragModel: G1DragModel.instance,
        sightHeight: U.Units.inchToM(1.6),
        zeroRange: U.Units.yardsToM(200),
        atmosphere: Atmosphere.standardIcao(),
        wind: const Wind.calm(),
        spinDrift: spinDrift,
        twistIn: twistIn,
        lengthIn: lengthIn,
        losAngleRad: losAngleDeg * 3.141592653589793 / 180.0,
        cantAngleRad: cantAngleRad,
      );

  group('Spin drift', () {
    test('spin drift adds rightward windage at range (right-hand twist)', () {
      final noSpin = baseConfig(spinDrift: false);
      final withSpin = baseConfig(spinDrift: true);
      final t1 = BallisticsSolver(noSpin)
          .solve(maxRangeM: U.Units.yardsToM(800), stepM: U.Units.yardsToM(100));
      final t2 = BallisticsSolver(withSpin)
          .solve(maxRangeM: U.Units.yardsToM(800), stepM: U.Units.yardsToM(100));
      final at700 = (List<TrajectoryPoint> t) => t.reduce((TrajectoryPoint a, TrajectoryPoint b) =>
          (a.range - U.Units.yardsToM(700)).abs() <
                  (b.range - U.Units.yardsToM(700)).abs()
              ? a
              : b);
      final w1 = at700(t1).windage;
      final w2 = at700(t2).windage;
      // spin drift is to the right (+y) for RH twist, so w2 > w1.
      expect(w2, greaterThan(w1));
      // magnitude at 700yd is a few inches (a few cm) for a .308.
      expect((w2 - w1), greaterThan(0.02)); // > ~1 inch
    });

    test('spin drift disabled -> identical to no-spin', () {
      final a = baseConfig(spinDrift: false);
      final b = baseConfig(spinDrift: true, twistIn: 0); // twistIn=0 disables
      final t1 = BallisticsSolver(a)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      final t2 = BallisticsSolver(b)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      for (int i = 0; i < t1.length; i++) {
        expect(t2[i].windage, closeTo(t1[i].windage, 1e-9));
      }
    });
  });

  group('Angle fire', () {
    test('uphill fire reduces drop (effective gravity smaller)', () {
      final level = baseConfig(losAngleDeg: 0);
      final uphill = baseConfig(losAngleDeg: 30);
      final t1 = BallisticsSolver(level)
          .solve(maxRangeM: U.Units.yardsToM(600), stepM: U.Units.yardsToM(100));
      final t2 = BallisticsSolver(uphill)
          .solve(maxRangeM: U.Units.yardsToM(600), stepM: U.Units.yardsToM(100));
      final at5 = (List<TrajectoryPoint> t) => t.reduce((TrajectoryPoint a, TrajectoryPoint b) =>
          (a.range - U.Units.yardsToM(500)).abs() <
                  (b.range - U.Units.yardsToM(500)).abs()
              ? a
              : b);
      // With less effective gravity, the bullet drops LESS (drop is less negative).
      expect(at5(t2).drop, greaterThan(at5(t1).drop));
    });

    test('downhill also reduces |drop| (symmetric in cos)', () {
      final level = baseConfig(losAngleDeg: 0);
      final downhill = baseConfig(losAngleDeg: -30);
      final t1 = BallisticsSolver(level)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      final t2 = BallisticsSolver(downhill)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      final at4 = (List<TrajectoryPoint> t) => t.reduce((TrajectoryPoint a, TrajectoryPoint b) =>
          (a.range - U.Units.yardsToM(400)).abs() <
                  (b.range - U.Units.yardsToM(400)).abs()
              ? a
              : b);
      expect(at4(t2).drop, greaterThan(at4(t1).drop));
    });
  });

  group('Truing (drop truing)', () {
    test('truing recovers the original BC (self-consistency)', () {
      // Use a known BC, compute its drop at 500yd, then truing should return ~BC.
      final cfg = baseConfig(bcOverride: 0.505);
      final solver = BallisticsSolver(cfg);
      final rangeM = U.Units.yardsToM(500);
      final observed = solver.dropAtRange(rangeM);
      final trued = solver.truedBc(rangeM: rangeM, observedDropM: observed);
      expect(trued, isNotNull);
      expect(trued!, closeTo(0.505, 0.02)); // within ~4%
    });

    test('lower observed drop -> higher trued BC', () {
      final cfg = baseConfig(bcOverride: 0.505);
      final solver = BallisticsSolver(cfg);
      final rangeM = U.Units.yardsToM(500);
      final base = solver.dropAtRange(rangeM);
      // A less-negative observed drop (bullet hitting higher) implies higher BC.
      // Use ±5% so both observations stay inside the solver's [0.4x, 2x] band.
      final truedHi = solver.truedBc(rangeM: rangeM, observedDropM: base * 0.95);
      final truedLo = solver.truedBc(rangeM: rangeM, observedDropM: base * 1.05);
      expect(truedHi, isNotNull);
      expect(truedLo, isNotNull);
      expect(truedHi!, greaterThan(truedLo!));
    });

    test('returns null when observed drop is physically impossible', () {
      final cfg = baseConfig(bcOverride: 0.505);
      final solver = BallisticsSolver(cfg);
      // A drop of +10m (bullet 10m ABOVE LOS at 500yd) is impossible for any BC.
      final trued = solver.truedBc(
          rangeM: U.Units.yardsToM(500), observedDropM: 10.0);
      expect(trued, isNull);
    });
  });

  group('dropAtRange', () {
    test('drop at zero range is ~0', () {
      final cfg = baseConfig();
      final solver = BallisticsSolver(cfg);
      final z = solver.dropAtRange(U.Units.yardsToM(200));
      expect(z.abs(), lessThan(0.03)); // within 3cm of LOS
    });

    test('drop becomes more negative with range', () {
      final cfg = baseConfig();
      final solver = BallisticsSolver(cfg);
      final d300 = solver.dropAtRange(U.Units.yardsToM(300));
      final d600 = solver.dropAtRange(U.Units.yardsToM(600));
      expect(d600, lessThan(d300));
    });
  });

  group('Lead (moving target)', () {
    test('lead grows with target speed', () {
      final cfg = baseConfig();
      final solver = BallisticsSolver(cfg);
      final range = U.Units.yardsToM(500);
      final l1 = solver.leadAt(targetSpeedMps: 2, rangeM: range);
      final l2 = solver.leadAt(targetSpeedMps: 4, rangeM: range);
      expect(l1, isNotNull);
      expect(l2, isNotNull);
      expect(l2!, closeTo(2 * l1!, 1e-6)); // linear in speed
    });

    test('lead increases with range (longer time of flight)', () {
      final cfg = baseConfig();
      final solver = BallisticsSolver(cfg);
      final near = solver.leadAt(targetSpeedMps: 3, rangeM: U.Units.yardsToM(300));
      final far = solver.leadAt(targetSpeedMps: 3, rangeM: U.Units.yardsToM(800));
      expect(near, isNotNull);
      expect(far, isNotNull);
      expect(far!, greaterThan(near!));
    });

    test('leadToAngle converts linear to angular', () {
      // 1m lead at 100m -> 0.01 rad
      expect(BallisticsSolver.leadToAngle(1.0, 100.0), closeTo(0.01, 1e-9));
    });
  });

  group('Transonic range', () {
    test('.308 goes transonic eventually (high-BC bullet flies far)', () {
      final cfg = baseConfig(); // 175gr .308 BC=0.505 @ 2600fps
      final solver = BallisticsSolver(cfg);
      final t = solver.transonicRange();
      expect(t, isNotNull);
      // High-BC .308 stays supersonic far; Mach 1.2 crossover ~1500-2500 yd.
      final yd = t! * 1.09361;
      expect(yd, greaterThan(1500));
      expect(yd, lessThan(2500));
    });

    test('higher-threshold triggers earlier', () {
      final cfg = baseConfig();
      final solver = BallisticsSolver(cfg);
      final t12 = solver.transonicRange(machThreshold: 1.2)!;
      final t15 = solver.transonicRange(machThreshold: 1.5)!;
      expect(t15, lessThan(t12));
    });
  });

  group('Aerodynamic jump', () {
    test('right crosswind -> downward jump for RH twist (negative)', () {
      final cfg = baseConfig();
      final solver = BallisticsSolver(cfg);
      // positive drift (right) -> negative jump (down) per Litz approx
      final jump = solver.aerodynamicJump(driftRad: 0.01, sg: 1.5);
      expect(jump, lessThan(0));
    });

    test('zero drift -> zero jump', () {
      final cfg = baseConfig();
      final solver = BallisticsSolver(cfg);
      expect(solver.aerodynamicJump(driftRad: 0, sg: 2.0), closeTo(0, 1e-12));
    });
  });

  group('Cant angle', () {
    test('zero cant leaves trajectory unchanged', () {
      final a = baseConfig(cantAngleRad: 0);
      final b = baseConfig(cantAngleRad: 0.001); // ~0.06deg, negligible
      final t1 = BallisticsSolver(a)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      final t2 = BallisticsSolver(b)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      // A 0.057° cant rotates a ~1.2m drop into ~0.001m of windage at 500yd,
      // so use 3e-3 tolerance (physics-correct; 1e-3 was too tight).
      for (int i = 0; i < t1.length; i++) {
        expect(t2[i].drop, closeTo(t1[i].drop, 3e-3));
        expect(t2[i].windage, closeTo(t1[i].windage, 3e-3));
      }
    });

    test('canted shot transfers drop into windage', () {
      final level = baseConfig(cantAngleRad: 0);
      final canted = baseConfig(cantAngleRad: 30 * 3.14159 / 180);
      final t1 = BallisticsSolver(level)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      final t2 = BallisticsSolver(canted)
          .solve(maxRangeM: U.Units.yardsToM(500), stepM: U.Units.yardsToM(100));
      // A rightward cant should introduce positive windage (bullet drifts right)
      // and reduce the magnitude of the drop at the same range.
      final at4 = (List<TrajectoryPoint> t) => t.reduce((TrajectoryPoint a, TrajectoryPoint b) =>
          (a.range - U.Units.yardsToM(400)).abs() <
                  (b.range - U.Units.yardsToM(400)).abs()
              ? a
              : b);
      expect(at4(t2).windage.abs(), greaterThan(at4(t1).windage.abs()));
    });
  });
}
