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
