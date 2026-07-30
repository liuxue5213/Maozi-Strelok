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
  static double hpaToPa(double hpa) => hpa * paPerHpa;

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
}

/// A unit-system preference used by the UI layer.
enum UnitSystem { metric, imperial }
