import 'dart:math';

/// Unit conversions between metric and imperial systems, and angular units.
///
/// All internal ballistics computations are done in SI units:
///   distance -> meters, velocity -> m/s, mass -> kg, energy -> joules.
/// These helpers translate user-facing imperial values into SI and back.
class Units {
  Units._();

  // --- Length ---
  static const double feetPerMeter = 3.28084;
  static const double yardsPerMeter = 1.09361;
  static const double inchPerMeter = 39.3701;

  static double mToFeet(double m) => m * feetPerMeter;
  static double feetToM(double ft) => ft / feetPerMeter;
  static double mToYards(double m) => m * yardsPerMeter;
  static double yardsToM(double yd) => yd / yardsPerMeter;
  static double mToInch(double m) => m * inchPerMeter;
  static double inchToM(double inch) => inch / inchPerMeter;

  // --- Mass ---
  static const double grainsPerPound = 7000;
  static const double kgPerPound = 0.45359237;

  static double grainToKg(double gr) => gr / grainsPerPound * kgPerPound;
  static double kgToGrain(double kg) => kg / kgPerPound * grainsPerPound;

  // --- Velocity ---
  static double fpsToMps(double fps) => fps / feetPerMeter;
  static double mpsToFps(double mps) => mps * feetPerMeter;
  static double kmhToMps(double kmh) => kmh / 3.6;
  static double mpsToKmh(double mps) => mps * 3.6;
  static double mphToMps(double mph) => mph * 0.44704;
  static double mpsToMph(double mps) => mps / 0.44704;

  // --- Energy ---
  static double jouleToFtLbf(double j) => j / 1.3558179483314;
  static double ftLbfToJoule(double ftlbf) => ftlbf * 1.3558179483314;

  // --- Pressure ---
  static const double paPerInHg = 3386.39; // inches of mercury -> pascals
  static const double paPerMmHg = 133.322;
  static const double paPerHpa = 100;

  static double inHgToPa(double inhg) => inhg * paPerInHg;
  static double paToInHg(double pa) => pa / paPerInHg;
  static double hpaToPa(double hpa) => hpa * paPerHpa;
  static double paToHpa(double pa) => pa / paPerHpa;
  static double mmHgToPa(double mmhg) => mmhg * paPerMmHg;
  static double psiToPa(double psi) => psi * 6894.757293168; // PSI -> pascals

  // --- Angular: IPHY (inches per hundred yards) ---
  // 1 IPHY = 1 MOA exactly (1 MOA ≈ 1.047" at 100yd, but IPHY is defined as
  // 1.000" at 100yd). Many US scopes are graduated in IPHY/"shooter's MOA".
  static const double radPerIphy = 0.0002908882086657216; // = 1 MOA for practical use
  static double iphyToRad(double iphy) => iphy * radPerIphy;
  static double radToIphy(double rad) => rad / radPerIphy;

  // --- Density Altitude (DA) utilities ---
  // Convert a density altitude (feet, ISA-relative) to an air density ratio
  // (rho/rho0) using the ISA troposphere model. rho0 = sea-level ISA density.
  static const double isaTropopauseFt = 36089.0; // ~11000 m
  static const double rho0KgM3 = 1.225;

  /// ISA air-density ratio for a given density altitude [ft].
  /// Below the tropopause DA decreases density by ~2.54e-6 per ft (exponential).
  static double densityRatioFromDaFt(double daFt) {
    if (daFt <= isaTropopauseFt) {
      // Troposphere: rho/rho0 = (1 - 6.875e-6 * h)^4.256
      final t = 1.0 - 6.87535e-6 * daFt;
      return t <= 0 ? 0.0 : pow(t, 4.2558793).toDouble();
    }
    // Stratosphere (isothermal): exponential decay above tropopause.
    final ratioAtTrop = densityRatioFromDaFt(isaTropopauseFt);
    final extraFt = daFt - isaTropopauseFt;
    return ratioAtTrop * exp(-extraFt / 10417.0); // scale height ~10417 ft
  }

  /// Air density [kg/m^3] from a density altitude [ft].
  static double densityFromDaFt(double daFt) =>
      rho0KgM3 * densityRatioFromDaFt(daFt);

  // --- Temperature ---
  static double fToC(double f) => (f - 32) / 1.8;
  static double cToF(double c) => c * 1.8 + 32;
  static double cToK(double c) => c + 273.15;

  // --- Angular ---
  // 1 MOA = 1/60 degree; at distance R it subtends R * tan(MOA) ≈ R * MOA_rad.
  static const double radPerDegree = 0.017453292519943295;
  static const double radPerMoa = 0.0002908882086657216; // pi/(180*60)
  // 1 MIL (NATO) = 1/6400 circle; milliradian variant = 1/1000 rad.
  static const double radPerMilNato =
      2 * 3.141592653589793 / 6400; // ~0.0009817477
  static const double radPerMrad = 0.001;

  static double moaToRad(double moa) => moa * radPerMoa;
  static double radToMoa(double rad) => rad / radPerMoa;
  static double milToRad(double mil) => mil * radPerMilNato;
  static double radToMil(double rad) => rad / radPerMilNato;
  static double degToRad(double deg) => deg * radPerDegree;

  /// Linear displacement (meters) subtended by an angular value at range R.
  static double angularToLinear(double angularRad, double rangeM) =>
      rangeM * angularRad;

  /// Angular (radians) needed to displace a linear offset at range R.
  static double linearToAngular(double linearM, double rangeM) =>
      linearM / rangeM;

  // ---- Wind speed display units ('mph' | 'ms' | 'kmh') ----
  // Storage stays mph everywhere (AppState / WindZoneInput); these convert
  // only at the UI boundary.

  static double windFromMph(double mph, String unit) => switch (unit) {
        'ms' => mph * 0.44704,
        'kmh' => mph * 1.609344,
        _ => mph,
      };

  static double windToMph(double value, String unit) => switch (unit) {
        'ms' => value / 0.44704,
        'kmh' => value / 1.609344,
        _ => value,
      };

  static String windUnitLabel(String unit) =>
      switch (unit) { 'ms' => 'm/s', 'kmh' => 'km/h', _ => 'mph' };
}

/// A unit-system preference used by the UI layer.
enum UnitSystem { metric, imperial }
