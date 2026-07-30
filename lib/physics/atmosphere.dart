import 'dart:math';

/// ICAO/US Standard Atmosphere model for computing air density, the speed of
/// sound, and gravity as a function of altitude and local weather conditions.
///
/// Drag is extremely sensitive to air density, so it must be computed from the
/// actual temperature, pressure and humidity at the firing point, not assumed.
class Atmosphere {
  /// Temperature [°C] at firing point.
  final double temperatureC;

  /// Barometric pressure [Pa] at firing point.
  final double pressurePa;

  /// Relative humidity [0..1].
  final double relativeHumidity;

  /// Altitude above sea level [m].
  final double altitudeM;

  Atmosphere({
    required this.temperatureC,
    required this.pressurePa,
    required this.relativeHumidity,
    this.altitudeM = 0,
  });

  /// ICAO standard atmosphere at sea level (15°C, 101325 Pa, 0%RH).
  factory Atmosphere.standardIcao() => Atmosphere(
        temperatureC: 15.0,
        pressurePa: 101325.0,
        relativeHumidity: 0.0,
        altitudeM: 0.0,
      );

  /// Temperature in Kelvin.
  double get temperatureK => temperatureC + 273.15;

  /// Saturation vapor pressure of water (Pa) via the Magnus formula.
  double get saturationVaporPressure {
    // Magnus / Tetens: e_s = 0.61094 * exp(17.625*T/(T+243.04)) [kPa]
    final t = temperatureC;
    final esKpa = 0.61094 * exp((17.625 * t) / (t + 243.04));
    return esKpa * 1000.0; // -> Pa
  }

  /// Actual vapor pressure [Pa].
  double get vaporPressure =>
      saturationVaporPressure * relativeHumidity.clamp(0.0, 1.0);

  /// Virtual temperature [K].
  /// Used so the ideal gas law with dry-air gas constant yields correct density
  /// for humid air.
  double get virtualTemperatureK {
    final e = vaporPressure;
    final p = pressurePa;
    return temperatureK / (1.0 - (e / p) * (1.0 - 0.622));
  }

  /// Air density [kg/m^3].
  /// rho = P / (R_dry * T_virtual)
  double get density {
    const rDry = 287.058; // J/(kg·K) specific gas constant for dry air
    return pressurePa / (rDry * virtualTemperatureK);
  }

  /// Speed of sound [m/s]:  c = sqrt(gamma * R * T)
  double get speedOfSound {
    const gamma = 1.4; // ratio of specific heats for air
    const r = 287.058; // J/(kg·K)
    return sqrt(gamma * r * temperatureK);
  }

  /// Mach number for a given speed [m/s].
  double machFor(double speedMs) => speedMs / speedOfSound;

  /// Gravitational acceleration [m/s^2] at the given altitude.
  /// WGS84 g0 reduced with altitude: g(h) = g0 * (R/(R+h))^2
  double get gravity {
    const g0 = 9.80665;
    const earthRadius = 6371000.0; // m
    final ratio = earthRadius / (earthRadius + altitudeM);
    return g0 * ratio * ratio;
  }
}
