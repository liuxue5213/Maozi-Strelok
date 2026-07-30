import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/atmosphere.dart';

void main() {
  group('Atmosphere (ICAO)', () {
    test('sea-level standard density ~ 1.225 kg/m^3', () {
      final a = Atmosphere.standardIcao();
      // Dry air, 15°C, 101325 Pa -> 1.225 kg/m^3
      expect(a.density, closeTo(1.225, 0.005));
    });

    test('speed of sound at 15°C ~ 340.3 m/s', () {
      final a = Atmosphere.standardIcao();
      expect(a.speedOfSound, closeTo(340.3, 0.5));
    });

    test('gravity at sea level ~ 9.80665', () {
      final a = Atmosphere.standardIcao();
      expect(a.gravity, closeTo(9.80665, 1e-3));
    });

    test('humidity reduces air density', () {
      final dry = Atmosphere(temperatureC: 20, pressurePa: 101325, relativeHumidity: 0);
      final humid = Atmosphere(temperatureC: 20, pressurePa: 101325, relativeHumidity: 1.0);
      expect(humid.density, lessThan(dry.density));
    });

    test('higher altitude reduces density', () {
      final sea = Atmosphere(temperatureC: 15, pressurePa: 101325, relativeHumidity: 0);
      final high = Atmosphere(
        temperatureC: 15,
        pressurePa: 70000,
        relativeHumidity: 0,
        altitudeM: 2500,
      );
      expect(high.density, lessThan(sea.density));
    });

    test('mach number matches speed/sound', () {
      final a = Atmosphere.standardIcao();
      expect(a.machFor(a.speedOfSound), closeTo(1.0, 1e-9));
      expect(a.machFor(680), closeTo(680 / 340.3, 0.01));
    });
  });
}
