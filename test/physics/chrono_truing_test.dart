import 'package:flutter_test/flutter_test.dart';

import 'package:ballistics_calculator/physics/atmosphere.dart';
import 'package:ballistics_calculator/physics/ballistics_solver.dart';
import 'package:ballistics_calculator/physics/units.dart' as U;

/// Chronograph-to-muzzle extrapolation: a chrono placed downrange reads LESS
/// than the muzzle velocity. Solve for the MV that reproduces the reading and
/// check the round trip recovers the original velocity.
void main() {
  ShotConfig config(double mvFps) {
    return ShotConfig(
      muzzleVelocity: mvFps / 3.28084,
      mass: 0.0109, // 168 gr
      diameter: 0.00782, // .308 cal
      bc: 0.462, // G1
      dragModel: 'G1',
      sightHeight: U.Units.inchToM(1.7),
      zeroRange: U.Units.yardsToM(100),
      atmosphere: Atmosphere.standardIcao(),
      wind: Wind.calm(),
      spinDrift: false,
      twistIn: 0,
      lengthIn: 0,
      losAngleRad: 0,
    );
  }

  test('extrapolation recovers the true MV from a 10yd chrono reading', () {
    const trueMvFps = 2600.0;
    const chronoYd = 10.0;
    final truth = BallisticsSolver(config(trueMvFps));
    final chronoSpeed = truth.speedAtRange(U.Units.yardsToM(chronoYd));

    // the reading must be lower than the muzzle velocity
    expect(chronoSpeed, lessThan(trueMvFps / 3.28084));

    final estimate = BallisticsSolver(config(2500)) // different starting MV
        .truedMvByChrono(
            chronoSpeedMps: chronoSpeed,
            chronoRangeM: U.Units.yardsToM(chronoYd));

    expect(estimate, isNotNull);
    expect(estimate!, closeTo(trueMvFps / 3.28084, 0.3)); // < 1 fps error
  });

  test('faster rounds lose more speed over the same chrono distance', () {
    final s2600 = BallisticsSolver(config(2600))
        .speedAtRange(U.Units.yardsToM(10));
    final s3400 = BallisticsSolver(config(3400))
        .speedAtRange(U.Units.yardsToM(10));
    expect(3400 / 3.28084 - s3400, greaterThan(2600 / 3.28084 - s2600));
  });

  test('reading out of the ±30% band returns null instead of garbage', () {
    final estimate = BallisticsSolver(config(2600)).truedMvByChrono(
        chronoSpeedMps: 2600 / 3.28084 * 1.5, // impossible: faster at range
        chronoRangeM: U.Units.yardsToM(10));
    expect(estimate, isNull);
  });
}
