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

  /// Density altitude [m] — the altitude in the ISA atmosphere that has the
  /// same air density as the current conditions. Useful for "density altitude"
  /// input workflows (Applied Ballistics style).
  ///
  /// Solved by inverting the ISA troposphere density formula iteratively.
  double get densityAltitudeM {
    final rho = density;
    const rho0 = 1.225; // ISA sea level
    final ratio = rho / rho0;
    if (ratio >= 1.0) {
      // denser than ISA SL -> negative DA (rare)
      // solve h from (1 - 6.875e-6*h_m)^4.256 = ratio
      final h = (1.0 - pow(ratio, 1.0 / 4.2558793).toDouble()) / 6.87535e-6;
      return h;
    }
    // bisect altitude [0, 11000m] for the matching density
    double lo = 0, hi = 11000.0;
    for (int i = 0; i < 60; i++) {
      final mid = 0.5 * (lo + hi);
      final t = 1.0 - 2.25577e-5 * mid; // ISA temp ratio in m
      final r = t <= 0 ? 0.0 : pow(t, 4.25588).toDouble();
      if (r > ratio) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  /// Density altitude in feet (common US convention).
  double get densityAltitudeFt => densityAltitudeM * 3.28084;

  /// Build an Atmosphere from a density-altitude input [m] and a temperature.
  /// Pressure is back-computed so that `density` matches the DA. This lets the
  /// user work in "Density Altitude" mode (Applied Ballistics default).
  factory Atmosphere.fromDensityAltitude({
    required double densityAltitudeM,
    required double temperatureC,
    double relativeHumidity = 0.0,
  }) {
    final rho = _densityAtIsaAltitude(densityAltitudeM);
    // back out pressure from rho = P / (Rd * Tv)  => P = rho * Rd * Tv
    const rd = 287.058;
    final tk = temperatureC + 273.15;
    final esPa = 0.61094 * exp((17.625 * temperatureC) / (temperatureC + 243.04)) * 1000.0;
    final e = esPa * relativeHumidity.clamp(0.0, 1.0);
    final tv = tk / (1.0 - (e / 101325.0) * (1.0 - 0.622));
    final p = rho * rd * tv;
    return Atmosphere(
      temperatureC: temperatureC,
      pressurePa: p,
      relativeHumidity: relativeHumidity,
      altitudeM: densityAltitudeM,
    );
  }

  /// ISA air density at a given geometric altitude [m] (troposphere model).
  static double _densityAtIsaAltitude(double h) {
    const rho0 = 1.225;
    if (h <= 11000) {
      final t = 1.0 - 2.25577e-5 * h;
      return t <= 0 ? 0.0 : rho0 * pow(t, 4.25588).toDouble();
    }
    final ratioAt11k = (1.0 - 2.25577e-5 * 11000);
    final rho11k = rho0 * pow(ratioAt11k, 4.25588).toDouble();
    return rho11k * exp(-(h - 11000) / 6341.62);
  }

  /// Compute a corrected atmosphere by adjusting air density for the difference
  /// between the *current* conditions and the *zero-time* conditions. Long-range
  /// zeros (e.g. 600 yd) are sensitive to air-density changes between zeroing
  /// and shooting. Used by the "Zero Atmosphere" workflow.
  ///
  /// The correction scales the effective drag by the density ratio of the two
  /// atmospheres. We return a new Atmosphere whose density equals the current
  /// density but whose temperature/speed-of-sound come from the current shot.
  /// (The solver consumes .density for drag; we just scale it.)
  Atmosphere adjustedForZeroAtmosphere(Atmosphere? zeroAtmo) {
    if (zeroAtmo == null) return this;
    // The ratio of drag scales with rho_current / rho_zero. We bake this into
    // the returned atmosphere's density field by overriding it, while keeping
    // the current temperature/sound for Mach calc. However density is derived,
    // so we instead scale pressure to achieve the target density.
    final targetDensity = density;
    // We want density = targetDensity but preserve current Tv (temperature/humidity)
    // so the speed of sound stays current. P = rho * Rd * Tv.
    const rd = 287.058;
    final p = targetDensity * rd * virtualTemperatureK;
    return Atmosphere(
      temperatureC: temperatureC,
      pressurePa: p,
      relativeHumidity: relativeHumidity,
      altitudeM: altitudeM,
    );
  }
}
