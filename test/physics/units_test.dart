import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/units.dart';

void main() {
  group('Units conversions', () {
    test('length conversions round-trip', () {
      expect(Units.feetToM(Units.mToFeet(10)), closeTo(10, 1e-9));
      expect(Units.yardsToM(Units.mToYards(10)), closeTo(10, 1e-9));
      expect(Units.inchToM(Units.mToInch(10)), closeTo(10, 1e-9));
    });

    test('mass: grain <-> kg', () {
      // 1 grain = 64.79891 mg
      expect(Units.grainToKg(1), closeTo(0.00006479891, 1e-9));
      expect(Units.kgToGrain(Units.grainToKg(150)), closeTo(150, 1e-6));
    });

    test('velocity: fps <-> m/s', () {
      expect(Units.fpsToMps(Units.mpsToFps(900)), closeTo(900, 1e-6));
      // 1 fps = 0.3048 m/s; the feet-per-meter constant is a finite-precision
      // approximation (3.28084), so tolerance is 1e-7 not 1e-9.
      expect(Units.fpsToMps(1), closeTo(0.3048, 1e-7));
    });

    test('energy: joule <-> ft-lbf', () {
      // 1 ft-lbf = 1.3558179 J
      expect(Units.ftLbfToJoule(1), closeTo(1.3558179483, 1e-7));
      expect(Units.jouleToFtLbf(1355.8179), closeTo(1000, 1e-3));
    });

    test('angular: MOA <-> rad', () {
      // 1 MOA at 100 yards ~ 1.047 inch ~ 0.02658 m
      final oneMoaRad = Units.moaToRad(1);
      final lin = Units.angularToLinear(oneMoaRad, 91.44); // 100yd in m
      expect(lin, closeTo(0.0266, 0.0005));
    });

    test('temperature: F <-> C <-> K', () {
      expect(Units.fToC(32), closeTo(0, 1e-9));
      expect(Units.fToC(212), closeTo(100, 1e-9));
      expect(Units.cToK(0), closeTo(273.15, 1e-9));
    });
  });
}
