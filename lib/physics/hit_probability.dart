import 'dart:math';

/// Hit-probability estimate.
///
/// Combines several independent, normally-distributed error sources into a
/// single circular standard deviation, then computes the probability that a
/// shot lands within a target of a given size at a given range.
///
/// The model is the standard "error budget" used by Applied Ballistics: each
/// contributor is a 1-sigma angular error; they combine in quadrature.
class HitProbability {
  HitProbability._();

  /// Combine independent 1-sigma angular errors (radians) in quadrature.
  static double combinedSigmaRad(List<double> sigmaRad) {
    var sumSq = 0.0;
    for (final s in sigmaRad) {
      sumSq += s * s;
    }
    return sqrt(sumSq);
  }

  /// Probability of a hit for a circular target of radius [targetRadiusM] at
  /// range [rangeM], given a combined 1-sigma angular dispersion [sigmaRad].
  ///
  /// Uses the 2D Gaussian integral over a disk:
  ///   P = 1 - exp(-r^2 / (2 * sigma_lin^2))
  /// where sigma_lin = sigmaRad * range (linear 1-sigma at the target).
  /// This is the exact probability for a circular bivariate normal.
  static double circularP({
    required double targetRadiusM,
    required double rangeM,
    required double sigmaRad,
  }) {
    if (rangeM <= 0 || sigmaRad <= 0) return 0;
    final sigmaLin = sigmaRad * rangeM;
    final r2 = targetRadiusM * targetRadiusM;
    final s2 = sigmaLin * sigmaLin;
    return 1.0 - exp(-r2 / (2 * s2));
  }

  /// Build the per-shot 1-sigma angular error budget (radians) from the
  /// shooter's inputs. All inputs are angular or convert to angular at [rangeM].
  ///
  /// [gunMoa]  rifle inherent accuracy (1-sigma, MOA).
  /// [shooterMoa] shooter/position error (1-sigma, MOA).
  /// [windErrMph]  wind-estimation error (mph); converted via the trajectory's
  ///   wind drift sensitivity (driftM per mph) -> angular.
  /// [rangeErrYd]  range-estimation error (yd); converted via drop sensitivity
  ///   (dropM per yd) -> angular.
  static double sigmaRadFromBudget({
    required double gunMoa,
    required double shooterMoa,
    required double windErrMph,
    required double rangeErrYd,
    required double windDriftPerMphM,
    required double dropPerYdM,
    required double rangeM,
  }) {
    const radPerMoa = 0.0002908882086657216;
    final gun = gunMoa * radPerMoa;
    final shooter = shooterMoa * radPerMoa;
    // wind estimation error -> linear drift -> angular
    final windLin = windErrMph * windDriftPerMphM.abs();
    final windAng = rangeM > 0 ? windLin / rangeM : 0.0;
    // range estimation error -> linear drop change -> angular
    final rangeLin = rangeErrYd.abs() * dropPerYdM.abs();
    final rangeAng = rangeM > 0 ? rangeLin / rangeM : 0.0;
    return combinedSigmaRad([gun, shooter, windAng, rangeAng]);
  }
}

/// Weapon Employment Zone (WEZ) Monte-Carlo hit-probability analyzer.
///
/// Unlike the analytic [HitProbability], WEZ samples the full distribution of
/// each error source and counts how many shots land inside the target. This is
/// the method Applied Ballistics uses (Bryan Litz). It also identifies the
/// dominant error source by computing single-variable sweeps.
class Wez {
  Wez._();

  /// One Monte-Carlo shot sample: (verticalError, horizontalError) in radians
  /// at the target plane.
  static ({double v, double h}) _sample(
    _Rng rng, {
    required double gunMoa,
    required double shooterMoa,
    required double windErrMph,
    required double windDriftPerMphM,
    required double rangeErrYd,
    required double dropPerYdM,
    required double mvErrFps,
    required double dropPerFpsM,
    required double rangeM,
  }) {
    const radPerMoa = 0.0002908882086657216;
    // 1-sigma angular dispersions
    final gunV = rng.gauss() * gunMoa * radPerMoa;
    final gunH = rng.gauss() * gunMoa * radPerMoa;
    final shV = rng.gauss() * shooterMoa * radPerMoa;
    final shH = rng.gauss() * shooterMoa * radPerMoa;
    // wind estimation error -> linear -> angular
    final windH = rng.gauss() * windErrMph * windDriftPerMphM.abs() / rangeM;
    // range error -> drop change -> angular
    final rangeV = rng.gauss() * rangeErrYd.abs() * dropPerYdM.abs() / rangeM;
    // MV variation -> drop change -> angular
    final mvV = rng.gauss() * mvErrFps.abs() * dropPerFpsM.abs() / rangeM;
    return (v: gunV + shV + rangeV + mvV, h: gunH + shH + windH);
  }

  /// Run a WEZ simulation. Returns hit probability [0..1].
  ///
  /// [targetShape] 'circle' | 'rectangle' | 'ipsc'. For circle only [targetWIn]
  /// is used (diameter); for rectangle/ipsc use width x height.
  static double run({
    required int shots,
    required double rangeM,
    required double gunMoa,
    required double shooterMoa,
    required double windErrMph,
    required double windDriftPerMphM,
    required double rangeErrYd,
    required double dropPerYdM,
    double mvErrFps = 0,
    double dropPerFpsM = 0,
    required double targetWIn,
    double targetHIn = 0,
    String targetShape = 'circle',
    int? seed,
  }) {
    if (rangeM <= 0) return 0;
    final rng = _Rng(seed ?? DateTime.now().microsecondsSinceEpoch);
    final wRad = targetWIn * 0.0254 / rangeM;
    final hRad = (targetHIn <= 0 ? targetWIn : targetHIn) * 0.0254 / rangeM;
    final wRad2 = wRad / 2, hRad2 = hRad / 2;
    int hits = 0;
    for (int i = 0; i < shots; i++) {
      final e = _sample(
        rng,
        gunMoa: gunMoa,
        shooterMoa: shooterMoa,
        windErrMph: windErrMph,
        windDriftPerMphM: windDriftPerMphM,
        rangeErrYd: rangeErrYd,
        dropPerYdM: dropPerYdM,
        mvErrFps: mvErrFps,
        dropPerFpsM: dropPerFpsM,
        rangeM: rangeM,
      );
      bool hit;
      if (targetShape == 'circle') {
        hit = (e.v * e.v + e.h * e.h) <= (wRad2 * wRad2);
      } else {
        hit = e.v.abs() <= hRad2 && e.h.abs() <= wRad2;
      }
      if (hit) hits++;
    }
    return hits / shots;
  }
}

/// Deterministic Gaussian RNG (Box-Muller) so WEZ results are reproducible
/// for a given seed (useful for tests and stable UI display).
class _Rng {
  final int _state;
  static int _global = 1;
  _Rng([int? seed]) : _state = seed ?? (_global = (_global * 1103515245 + 12345) & 0x7fffffff);

  double _next() {
    // simple LCG for uniforms
    final next = (1103515245 * _state + 12345) & 0x7fffffff;
    _global = next;
    return next / 0x7fffffff;
  }

  double gauss() {
    final u1 = _next().clamp(1e-10, 1.0);
    final u2 = _next();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}
