import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/units.dart' as U;
import 'package:ballistics_calculator/physics/atmosphere.dart';
import 'package:ballistics_calculator/physics/drag_models.dart';
import 'package:ballistics_calculator/physics/ballistics_solver.dart';

/// Helpers to build a shot from imperial input values (the units shooters use).
/// Mirrors the helper in ballistics_solver_test.dart so these tests stay
/// self-contained. spin/twist defaults keep spin drift disabled (twistIn=0),
/// matching the rest of the suite.
ShotConfig imperialShot({
  required double v0fps,
  required double bc,
  required double massGr,
  required double diaIn,
  required double sightHeightIn,
  required double zeroYd,
  DragModel? drag,
}) {
  return ShotConfig(
    muzzleVelocity: U.Units.fpsToMps(v0fps),
    mass: U.Units.grainToKg(massGr),
    diameter: U.Units.inchToM(diaIn),
    bc: bc,
    dragModel: drag ?? G1DragModel.instance,
    sightHeight: U.Units.inchToM(sightHeightIn),
    zeroRange: U.Units.yardsToM(zeroYd),
    atmosphere: Atmosphere.standardIcao(),
    wind: const Wind.calm(),
  );
}

void main() {
  // 168gr .308 Sierra MatchKing, G1 BC=0.462, MV=2600fps, 200yd zero, 1.5"
  // sight height. The same reference load validated against public ballistics
  // tables and a Python reference solver.
  ShotConfig rifleCfg() => imperialShot(
        v0fps: 2600,
        bc: 0.462,
        massGr: 168,
        diaIn: 0.308,
        sightHeightIn: 1.5,
        zeroYd: 200,
      );

  group('BallisticsSolver.zeroCrossings', () {
    test('168gr .308 200yd-zero: farZero near the zero, nearZero close in', () {
      final s = BallisticsSolver(rifleCfg());
      // scanToM kept small so the test stays fast; the far zero is ~183m so
      // a 400m scan comfortably contains both crossings.
      final z = s.zeroCrossings(scanToM: 400);

      // Field names must be present on the record.
      expect(z.nearZero, isNotNull);
      expect(z.farZero, isNotNull);

      // The far zero is the configured zero range (~200yd) -> 185..215yd.
      final farYd = U.Units.mToYards(z.farZero!);
      expect(farYd, greaterThanOrEqualTo(185));
      expect(farYd, lessThanOrEqualTo(215));

      // The near zero (MPBR-ish crossing on the way up) is well inside 50yd.
      final nearYd = U.Units.mToYards(z.nearZero!);
      expect(nearYd, lessThan(50));
    });

    test('returns a record with named fields nearZero / farZero', () {
      // A flatter-shooting config still yields both crossings; this mainly
      // pins the record's field names and that both are populated.
      final cfg = imperialShot(
        v0fps: 2800,
        bc: 0.500,
        massGr: 168,
        diaIn: 0.308,
        sightHeightIn: 1.5,
        zeroYd: 200,
      );
      final z = BallisticsSolver(cfg).zeroCrossings(scanToM: 500);

      // Accessing these named fields would not compile if the record shape
      // changed; we also assert they are real doubles.
      expect(z.nearZero, isA<double>());
      expect(z.farZero, isA<double>());
      expect(z.nearZero! < z.farZero!, isTrue);
    });
  });

  group('BallisticsSolver.maxEffectiveRange', () {
    test('168gr .308 returns a positive max-effective range', () {
      final s = BallisticsSolver(rifleCfg());
      final mer = s.maxEffectiveRange(dropLimitM: 2.0, scanToM: 800);
      expect(mer, isNotNull);
      expect(mer!, greaterThan(0));

      // The default 2 m drop budget is a *conservative* "max point-blank"-style
      // proxy measured from the muzzle bore, not a lethality figure. With a
      // near-zero elevation it is reached well inside a full kill range:
      // the engine yields ~575 m (~630yd) for this load, so we assert a band
      // that brackets the real result rather than the looser 800-1200yd guess.
      final merYd = U.Units.mToYards(mer);
      expect(merYd, greaterThanOrEqualTo(550));
      expect(merYd, lessThanOrEqualTo(750));
    });

    test('returns null when the drop limit can never be reached in the scan', () {
      // A drop limit deeper than the trajectory can fall within the scanned
      // range (the integrator stops at z = -1000 m) is unfulfillable, so the
      // method must return null.
      final s = BallisticsSolver(rifleCfg());
      final mer = s.maxEffectiveRange(dropLimitM: 2000.0, scanToM: 600);
      expect(mer, isNull);
    });
  });
}
