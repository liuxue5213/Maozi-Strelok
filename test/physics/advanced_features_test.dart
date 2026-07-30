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
      );

  group('Spin drift', () {
    test('spin drift adds rightward windage at range (right-hand twist)', () {
      final noSpin = baseConfig(spinDrift: false);
      final withSpin = baseConfig(spinDrift: true);
      final t1 = BallisticsSolver(noSpin)
          .solve(maxRangeM: U.Units.yardsToM(800), stepM: U.Units.yardsToM(100));
      final t2 = BallisticsSolver(withSpin)
          .solve(maxRangeM: U.Units.yardsToM(800), stepM: U.Units.yardsToM(100));
      final at700 = (t) => t.reduce((a, b) =>
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
      final at5 = (t) => t.reduce((a, b) =>
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
      final at4 = (t) => t.reduce((a, b) =>
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
      final truedHi = solver.truedBc(rangeM: rangeM, observedDropM: base * 0.85);
      final truedLo = solver.truedBc(rangeM: rangeM, observedDropM: base * 1.15);
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
}
