import 'dart:math';
import 'units.dart';

/// Miller gyroscopic (twist) stability factor (Don Miller, *Precision Shooting*;
/// hosted by JBM Ballistics). This is the standard used by JBM, Applied
/// Ballistics and most commercial solvers.
///
///   Sg = 30 * m / (t^2 * d^3 * l * (1 + l^2)) * (v / 2800)^(1/3) * ft * fp
///
/// where:
///   m   = bullet mass [grains]
///   t   = twist rate [calibers per turn] = twist_in / d
///   d   = bullet diameter [in]
///   l   = bullet length [calibers] = len_in / d
///   v   = muzzle velocity [ft/s]
///   ft  = temperature factor  = (T_std / T)^(1/2)   (T in Rankine)
///   fp  = pressure factor     = (P / P_std)
///   (velocity scaling fv = (v/2800)^(1/3); the "30" constant already
///    includes the standard 2800 fps, 59°F, 750 mmHg Army Metro baseline)
///
/// Sg >= 1.0  -> gyroscopically stable at the muzzle.
/// Sg >= 1.3  -> recommended margin (stable through transonic).
/// Sg >= 1.5  -> optimum.
class Stability {
  /// Standard sea-level air density [kg/m^3] (ICAO reference).
  static const double rho0 = 1.225;

  /// Army Standard Metro baseline: 59°F (518.67 R), 750 mmHg (29.53 inHg,
  /// ~100000 Pa), 78% RH — the conditions Miller's constant "30" assumes.
  static const double _tStdRankine = 518.67; // 59 °F in Rankine
  static const double _pStdPa = 29.53 * 3386.39; // ~100000 Pa

  /// Compute the Miller stability factor (gyroscopic stability Sg).
  ///
  /// [massGr] bullet mass (grains).
  /// [diaIn]  bullet diameter (inches).
  /// [lenIn]  bullet length (inches).
  /// [twistIn] barrel twist rate: inches per full turn.
  /// [v0fps]  muzzle velocity (ft/s).
  /// [airDensityKgM3] ambient air density (kg/m^3) — used to derive the
  ///   equivalent temperature/pressure factors for altitude effects.
  /// [temperatureC] ambient temperature (°C), default 15 (59°F standard).
  /// [pressurePa] ambient pressure (Pa), default ~100000 Pa (750 mmHg).
  static double millerSg({
    required double massGr,
    required double diaIn,
    required double lenIn,
    required double twistIn,
    required double v0fps,
    double airDensityKgM3 = rho0,
    double temperatureC = 15,
    double pressurePa = _pStdPa,
  }) {
    final t = twistIn / diaIn; // calibers per turn
    final l = lenIn / diaIn; // length in calibers
    final l2 = l * l;

    // Base stability (no velocity / atmosphere scaling): includes (1 + l^2).
    final base = (30.0 * massGr) / (t * t * diaIn * diaIn * diaIn * l * (1 + l2));

    // Velocity correction: fv = (v / 2800)^(1/3).
    final velFactor = pow(v0fps / 2800.0, 1.0 / 3.0).toDouble();

    // Atmosphere correction: Miller's constant 30 assumes standard air density
    // (59°F / 750 mmHg / 78% RH, ~1.225 kg/m3). Stability scales inversely with
    // air density: thinner air (high altitude) -> weaker aerodynamic restoring
    // moment -> higher Sg. This also matches JBM's density-based scaling.
    final rhoRatio = airDensityKgM3 / rho0;

    return base * velFactor / rhoRatio;
  }

  /// Human-readable stability assessment.
  static String assess(double sg) {
    if (sg < 1.0) return 'Unstable (Sg<1.0)';
    if (sg < 1.3) return 'Marginal (Sg<1.3)';
    if (sg < 1.5) return 'Stable (Sg<1.5)';
    return 'Optimal (Sg>=1.5)';
  }
}
