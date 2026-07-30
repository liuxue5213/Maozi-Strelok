import 'dart:math';
import 'units.dart';

/// Miller gyroscopic (twist) stability factor.
///
/// Sg = 30 * m / (rho_air/rho_0) / (t^2 * d^3 * l) * (v0 / (d * sqrt(gamma*R*T0)))
///   simplified Donovan-Miller form:
///
///   Sg = (30 * m) / ( rho' * t^2 * d^3 * l ) * sqrt(v0 / (7000 * d))
///        where rho' = rho_air / rho_0  (air density ratio, 1.225 kg/m^3)
///        t = twist rate [calibers per turn]
///        d = bullet diameter [in]
///        l = bullet length [calibers]
///        m = mass [grains]
///        v0 = muzzle velocity [ft/s]
///
/// Sg >= 1.0  -> gyroscopically stable at the muzzle.
/// Sg >= 1.3  -> recommended margin (stable through transonic).
/// Sg >= 1.5  -> optimum.
class Stability {
  /// Standard sea-level air density [kg/m^3] (ICAO).
  static const double rho0 = 1.225;

  /// Compute the Miller stability factor.
  ///
  /// [massGr] bullet mass (grains).
  /// [diaIn]  bullet diameter (inches).
  /// [lenIn]  bullet length (inches).
  /// [twistIn] barrel twist rate: inches per full turn.
  /// [v0fps]  muzzle velocity (ft/s).
  /// [airDensityKgM3] ambient air density (kg/m^3).
  static double millerSg({
    required double massGr,
    required double diaIn,
    required double lenIn,
    required double twistIn,
    required double v0fps,
    double airDensityKgM3 = rho0,
  }) {
    final t = twistIn / diaIn; // calibers per turn (dimensionless)
    final l = lenIn / diaIn; // length in calibers
    final rhoRatio = airDensityKgM3 / rho0;

    final base = (30.0 * massGr) /
        (rhoRatio * t * t * diaIn * diaIn * diaIn * l);
    final velFactor = sqrt(v0fps / (7000.0 * diaIn));
    return base * velFactor;
  }

  /// Human-readable stability assessment.
  static String assess(double sg) {
    if (sg < 1.0) return 'Unstable (Sg<1.0)';
    if (sg < 1.3) return 'Marginal (Sg<1.3)';
    if (sg < 1.5) return 'Stable (Sg<1.5)';
    return 'Optimal (Sg>=1.5)';
  }
}
