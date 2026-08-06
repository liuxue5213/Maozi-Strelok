import 'dart:math';

import 'atmosphere.dart';
import 'coriolis.dart';
import 'drag_models.dart';

/// A single point along the computed trajectory, sampled at a given range.
///
/// All linear values are in meters, angles in radians. "drop" is the bullet
/// path relative to the line of sight (LOS): negative = below the LOS,
/// positive = above it. "windage" is +right.
class TrajectoryPoint {
  /// Downrange distance [m].
  final double range;

  /// Bullet path relative to the LOS [m]. Negative = below the sight line.
  final double drop;

  /// Wind deflection (windage), +right [m].
  final double windage;

  /// Remaining speed [m/s].
  final double speed;

  /// Kinetic energy [J].
  final double energy;

  /// Time of flight [s].
  final double timeOfFlight;

  /// Sight come-up needed to hit at this range, relative to the zero [rad].
  /// Positive = raise the sight (bullet currently hitting low).
  final double comeUpRad;

  const TrajectoryPoint({
    required this.range,
    required this.drop,
    required this.windage,
    required this.speed,
    required this.energy,
    required this.timeOfFlight,
    required this.comeUpRad,
  });
}

/// Inputs that fully describe a shot, in SI units.
class ShotConfig {
  /// Muzzle velocity [m/s] (after any barrel-length / muzzle-device correction).
  final double muzzleVelocity;

  /// Bullet mass [kg].
  final double mass;

  /// Bullet diameter [m].
  final double diameter;

  /// Ballistic coefficient [lb/in^2] in the chosen drag model's standard.
  final double bc;

  /// Drag model to use.
  final DragModel dragModel;

  /// Sight height above the bore axis [m].
  final double sightHeight;

  /// Zero range [m] (range at which the bullet crosses the LOS on the way down).
  final double zeroRange;

  /// Optional fixed elevation angle [rad] above the LOS (skips zero solve).
  final double? elevationOverride;

  /// Atmosphere at the firing point.
  final Atmosphere atmosphere;

  /// Optional atmosphere present when the rifle was zeroed. When provided, the
  /// zero angle is solved under THIS atmosphere (matching the conditions where
  /// the zero was actually established), while the trajectory itself is
  /// integrated under [atmosphere]. This is the "Zero Atmosphere" feature of
  /// Applied Ballistics: a long-range zero taken at a different air density is
  /// corrected without re-zeroing. Null = zero solved at current atmosphere.
  final Atmosphere? zeroAtmosphere;

  /// Wind.
  final Wind wind;

  /// Optional multi-zone wind profile. When non-empty, this overrides [wind]:
  /// the solver samples the wind vector from the zone covering the bullet's
  /// current downrange position. Zones past their [toM] are skipped.
  final List<WindZone> windZones;

  /// Coriolis parameters (null disables the effect).
  final Coriolis? coriolis;

  /// Whether to compute spin drift (gyroscopic drift to the right for a
  /// right-hand-twist barrel). Default true.
  final bool spinDrift;

  /// Barrel twist rate [in/turn]. Used for spin-drift magnitude (and mirrors
  /// the Modification's twist, kept here so the solver is self-contained).
  final double twistIn;

  /// Bullet length [in]. Used for spin-drift.
  final double lengthIn;

  /// Line-of-sight elevation angle [rad], +uphill. For uphill/downhill shooting
  /// the gravity component along the bore changes. 0 = level fire.
  final double losAngleRad;

  /// Rifle cant (roll) angle [rad]. A non-zero cant rotates the elevation and
  /// windage corrections into each other: a portion of the vertical drop becomes
  /// horizontal deflection and vice-versa. Applied as a post-process on the
  /// output points (it does not change the trajectory itself).
  final double cantAngleRad;

  /// Drop Scale Factors (DSF): per-range multipliers that scale the computed
  /// drop to match observed impacts. Keyed by range in meters; the value
  /// multiplies the drop at/around that range. Empty = no DSF (model drop used
  /// as-is). Used by the multi-point drop-truing workflow.
  final Map<double, double> dropScaleFactors;

  const ShotConfig({
    required this.muzzleVelocity,
    required this.mass,
    required this.diameter,
    required this.bc,
    required this.dragModel,
    required this.sightHeight,
    required this.zeroRange,
    this.elevationOverride,
    required this.atmosphere,
    this.zeroAtmosphere,
    required this.wind,
    this.coriolis,
    this.windZones = const [],
    this.spinDrift = true,
    this.twistIn = 0,
    this.lengthIn = 0,
    this.losAngleRad = 0,
    this.cantAngleRad = 0,
    this.dropScaleFactors = const {},
  });
}

  /// Wind in SI units. [directionDeg] is the bearing the wind blows FROM, measured
/// clockwise from the downrange (x) axis (x=downrange, +y=right):
///   0   -> headwind (from downrange, blowing toward the shooter),
///   90  -> from the right, pushing the bullet to the left (-y),
///   180 -> tailwind (from the shooter, blowing toward the target),
///   270 -> from the left, pushing the bullet to the right (+y).
class Wind {
  final double speedMs;
  final double directionDeg;

  const Wind({required this.speedMs, required this.directionDeg});

  const Wind.calm()
      : speedMs = 0,
        directionDeg = 0;

  /// Wind velocity vector (vx, vy) in the shooting frame [m/s].
  ({double vx, double vy}) get vector {
    final r = directionDeg * pi / 180.0;
    // Air moves toward the "to" direction = opposite of "from".
    return (vx: -speedMs * cos(r), vy: -speedMs * sin(r));
  }
}

/// A wind defined over a downrange segment [fromM, toM]. Multiple WindZone
/// entries let the shooter model non-uniform wind along the bullet's flight
/// (e.g. headwind at the firing point, crosswind in the valley, different wind
/// near the target). The solver picks the active zone at the bullet's current
/// downrange position during integration.
class WindZone {
  /// Start of this zone [m] (downrange).
  final double fromM;
  /// End of this zone [m]. Use double.infinity for "to the end".
  final double toM;
  final Wind wind;
  const WindZone({required this.fromM, required this.toM, required this.wind});
}

/// Projectile state during integration.
class _State {
  double x, y, z; // position [m]
  double vx, vy, vz; // velocity [m/s]
  _State(this.x, this.y, this.z, this.vx, this.vy, this.vz);
  _State copy() => _State(x, y, z, vx, vy, vz);
}

/// External-ballistics solver. Integrates the 3D equations of motion with a
/// fixed-step 4th-order Runge-Kutta (RK4) scheme.
///
/// Frame:
///   x = downrange along the LOS (horizontal),
///   y = cross-range (+right),
///   z = vertical (+up), LOS lies on z = 0.
/// The bullet starts at z = -sightHeight (bore below the sight).
class BallisticsSolver {
  static const double defaultDt = 1e-4;

  final ShotConfig config;
  final double dt;
  final double _crossArea; // pi*d^2/4
  final double _massGr;
  final double _diaIn;

  BallisticsSolver(this.config, {this.dt = defaultDt})
      : _crossArea = pi * config.diameter * config.diameter / 4.0,
        _massGr = config.mass / 0.45359237 * 7000.0,
        _diaIn = config.diameter * 39.3701;

  /// Effective gravity along the bullet's path. For uphill/downhill fire the
  /// gravity component in the plane of motion is g*cos(LOS angle); this is the
  /// standard simplified treatment used by commercial solvers. Level fire: g.
  double get _effectiveGravity =>
      config.atmosphere.gravity * cos(config.losAngleRad.abs());

  /// Solve the bore elevation angle [rad] that zeros the trajectory at the
  /// configured zero range (bisection on bullet height at zero range).
  ///
  /// If [ShotConfig.zeroAtmosphere] is set, the zero angle is solved under the
  /// zero-time atmosphere (a long-range zero established at different density
  /// is honored), while trajectory integration still uses [config.atmosphere].
  double solveZeroAngle() {
    if (config.elevationOverride != null) return config.elevationOverride!;
    final zr = config.zeroRange;
    if (zr <= 0) return 0;

    // Zero-angle solver that integrates under the given atmosphere.
    double zAtUnder(Atmosphere atmo, double theta) {
      final cfg = _withAtmosphere(atmo);
      return BallisticsSolver(cfg, dt: dt)._zAtRange(zr, theta);
    }

    final atmo = config.zeroAtmosphere ?? config.atmosphere;
    double zAt(double theta) => zAtUnder(atmo, theta);

    // We want z(zr) = 0 (bullet on the LOS at the zero range).
    double lo = -0.02, hi = 0.3;
    double fLo = zAt(lo);
    double fHi = zAt(hi);
    // Expand the bracket until it straddles 0.
    for (int i = 0; i < 80 && (fLo > 0) == (fHi > 0); i++) {
      hi += 0.05;
      fHi = zAt(hi);
    }
    // Bisection.
    for (int i = 0; i < 80; i++) {
      final mid = 0.5 * (lo + hi);
      final fMid = zAt(mid);
      if ((fLo > 0) != (fMid > 0)) {
        hi = mid;
        fHi = fMid;
      } else {
        lo = mid;
        fLo = fMid;
      }
    }
    return 0.5 * (lo + hi);
  }

  /// Bullet height z at [rangeM] for a given bore elevation.
  double _zAtRange(double rangeM, double elevation) {
    final states = _integrate(stopRange: rangeM, elevation: elevation);
    if (states.isEmpty) return 0;
    return states.last.z;
  }

  /// Copy of this config with a different atmosphere (keeps everything else,
  /// and drops any zeroAtmosphere so zero-solve doesn't recurse).
  ShotConfig _withAtmosphere(Atmosphere atmo) => ShotConfig(
        muzzleVelocity: config.muzzleVelocity,
        mass: config.mass,
        diameter: config.diameter,
        bc: config.bc,
        dragModel: config.dragModel,
        sightHeight: config.sightHeight,
        zeroRange: config.zeroRange,
        elevationOverride: config.elevationOverride,
        atmosphere: atmo,
        wind: config.wind,
        windZones: config.windZones,
        coriolis: config.coriolis,
        spinDrift: false,
        twistIn: 0,
        lengthIn: 0,
        losAngleRad: config.losAngleRad,
        cantAngleRad: config.cantAngleRad,
        dropScaleFactors: const {},
      );

  /// Acceleration a = a_drag(v_rel) + a_gravity + a_coriolis, written to [out].
  void _accel(_State s, double g, double rho, double cSound, List<double> out) {
    // Resolve wind: use multi-zone wind if provided, else the single wind.
    final ({double vx, double vy}) w;
    final zones = config.windZones;
    if (zones.isNotEmpty) {
      w = _windAt(s.x).vector;
    } else {
      w = config.wind.vector;
    }
    final vrx = s.vx - w.vx;
    final vry = s.vy - w.vy;
    final vrz = s.vz;
    final vr2 = vrx * vrx + vry * vry + vrz * vrz;
    final vr = sqrt(vr2);

    final mach = cSound > 0 ? vr / cSound : 0;
    final cd = config.dragModel.cd(mach, config.bc, _massGr, _diaIn);
    final dragMag = rho * cd * _crossArea * vr2 / (2.0 * config.mass);

    final invVr = vr > 1e-9 ? 1.0 / vr : 0.0;
    double ax = -dragMag * vrx * invVr;
    double ay = -dragMag * vry * invVr;
    double az = -dragMag * vrz * invVr - g;

    final cor = config.coriolis;
    if (cor != null && cor.isEnabled) {
      final c = cor.acceleration(s.vx, s.vy, s.vz);
      ax += c.ax;
      ay += c.ay;
      az += c.az;
    }
    out[0] = ax;
    out[1] = ay;
    out[2] = az;
  }

  /// One RK4 step.
  _State _rk4Step(_State s, double g, double rho, double cSound, double h) {
    final a = List<double>.filled(3, 0);

    _accel(s, g, rho, cSound, a);
    final k1vx = s.vx, k1vy = s.vy, k1vz = s.vz;
    final k1ax = a[0], k1ay = a[1], k1az = a[2];

    _accel(
        _State(
            s.x + 0.5 * h * k1vx,
            s.y + 0.5 * h * k1vy,
            s.z + 0.5 * h * k1vz,
            s.vx + 0.5 * h * k1ax,
            s.vy + 0.5 * h * k1ay,
            s.vz + 0.5 * h * k1az),
        g,
        rho,
        cSound,
        a);
    final k2vx = s.vx + 0.5 * h * k1ax;
    final k2vy = s.vy + 0.5 * h * k1ay;
    final k2vz = s.vz + 0.5 * h * k1az;
    final k2ax = a[0], k2ay = a[1], k2az = a[2];

    _accel(
        _State(
            s.x + 0.5 * h * k2vx,
            s.y + 0.5 * h * k2vy,
            s.z + 0.5 * h * k2vz,
            s.vx + 0.5 * h * k2ax,
            s.vy + 0.5 * h * k2ay,
            s.vz + 0.5 * h * k2az),
        g,
        rho,
        cSound,
        a);
    final k3vx = s.vx + 0.5 * h * k2ax;
    final k3vy = s.vy + 0.5 * h * k2ay;
    final k3vz = s.vz + 0.5 * h * k2az;
    final k3ax = a[0], k3ay = a[1], k3az = a[2];

    _accel(
        _State(
            s.x + h * k3vx,
            s.y + h * k3vy,
            s.z + h * k3vz,
            s.vx + h * k3ax,
            s.vy + h * k3ay,
            s.vz + h * k3az),
        g,
        rho,
        cSound,
        a);
    final k4ax = a[0], k4ay = a[1], k4az = a[2];

    final six = 1.0 / 6.0;
    return _State(
      s.x + h * six * (k1vx + 2 * k2vx + 2 * k3vx + (s.vx + h * k3ax)),
      s.y + h * six * (k1vy + 2 * k2vy + 2 * k3vy + (s.vy + h * k3ay)),
      s.z + h * six * (k1vz + 2 * k2vz + 2 * k3vz + (s.vz + h * k3az)),
      s.vx + h * six * (k1ax + 2 * k2ax + 2 * k3ax + k4ax),
      s.vy + h * six * (k1ay + 2 * k2ay + 2 * k3ay + k4ay),
      s.vz + h * six * (k1az + 2 * k2az + 2 * k3az + k4az),
    );
  }

  /// Integrate from the muzzle to [stopRange] (or ground), returning raw states.
  List<_State> _integrate(
      {required double stopRange, required double elevation}) {
    final g = _effectiveGravity;
    final rho = config.atmosphere.density;
    final cSound = config.atmosphere.speedOfSound;

    var s = _State(
        0,
        0,
        -config.sightHeight, // bore is sightHeight below the LOS
        config.muzzleVelocity * cos(elevation),
        0,
        config.muzzleVelocity * sin(elevation));

    final out = <_State>[s.copy()];
    final h = dt;
    while (s.x < stopRange && s.z > -1000) {
      final next = _rk4Step(s, g, rho, cSound, h);
      if (next.x <= s.x) break; // guard against backward motion
      s = next;
      out.add(s.copy());
    }
    return out;
  }

  /// Compute the full trajectory up to [maxRangeM], sampling at each [stepM].
  List<TrajectoryPoint> solve(
      {required double maxRangeM, double stepM = 100.0}) {
    final elevation = solveZeroAngle();
    final raw = _integrate(stopRange: maxRangeM, elevation: elevation);
    if (raw.length < 2) return [];

    final halfMass = config.mass * 0.5;
    final pts = <TrajectoryPoint>[];

    // Precompute spin-drift scale factor if enabled.
    // Litz gyroscopic drift (right-hand twist -> drift to the right, +y):
    //   drift_inches = 1.25 * (Sg + 1.2) * tof^1.83
    // where Sg is the Miller stability factor at the muzzle. We scale by
    // (reference_twist / actual_twist) to reflect twist rate.
    final bool useSpin = config.spinDrift && config.twistIn > 0 && config.lengthIn > 0;
    double sg = 0;
    if (useSpin) {
      // muzzle Mach-based Miller Sg
      const rho0 = 1.225;
      final t = config.twistIn / _diaIn;
      final l = config.lengthIn / _diaIn;
      final base = (30.0 * _massGr) /
          (rho0 * t * t * _diaIn * _diaIn * _diaIn * l);
      final v0fps = config.muzzleVelocity * 3.28084;
      sg = base * sqrt(v0fps / (7000.0 * _diaIn));
    }

    double nextSample = 0;
    int i = 0;
    while (nextSample <= maxRangeM + 1e-6) {
      while (i < raw.length - 1 && raw[i].x < nextSample) {
        i++;
      }
      if (i == 0) i = 1;
      final p0 = raw[i - 1];
      final p1 = raw[i];
      final spanx = p1.x - p0.x;
      final f = spanx.abs() > 1e-9 ? (nextSample - p0.x) / spanx : 0.0;
      final x = nextSample;
      double y = p0.y + f * (p1.y - p0.y);
      final z = p0.z + f * (p1.z - p0.z);
      final vx = p0.vx + f * (p1.vx - p0.vx);
      final vy = p0.vy + f * (p1.vy - p0.vy);
      final vz = p0.vz + f * (p1.vz - p0.vz);
      final tof = (i - 1 + f) * dt;
      final speed = sqrt(vx * vx + vy * vy + vz * vz);
      final energy = halfMass * speed * speed;

      // Spin (gyroscopic) drift, additive to windage.
      if (useSpin) {
        final driftIn = 1.25 * (sg + 1.2) * pow(tof, 1.83);
        y += driftIn * 0.0254; // inches -> meters, +right
      }

      // Rifle cant: rotate the (vertical drop, horizontal windage) pair by the
      // cant angle. A canted rifle transfers part of the elevation correction
      // into windage and vice-versa. drop is downward (z negative), windage +right.
      var dropZ = z;
      var windY = y;
      final cant = config.cantAngleRad;
      if (cant.abs() > 1e-9) {
        final cc = cos(cant);
        final sc = sin(cant);
        // rotate: drop stays along gravity but rifle frame is rolled.
        // newWindage = windage*cos - drop*sin ; newDrop = windage*sin + drop*cos
        // (using z as drop, where negative = low)
        final ny = windY * cc - dropZ * sc;
        final nz = windY * sc + dropZ * cc;
        windY = ny;
        dropZ = nz;
      }

      // Drop Scale Factor (DSF): scale the drop by an interpolated factor from
      // the user's multi-point truing data, so the model matches observed
      // impacts across several ranges.
      if (config.dropScaleFactors.isNotEmpty) {
        dropZ *= _dsfAt(x);
      }

      // Come-up (sight correction) to hit at this range: -drop/x, small angle.
      final comeUp = x > 1 ? -dropZ / x : 0.0;

      pts.add(TrajectoryPoint(
        range: x,
        drop: dropZ, // bullet path relative to LOS (LOS is z=0)
        windage: windY,
        speed: speed,
        energy: energy,
        timeOfFlight: tof,
        comeUpRad: comeUp,
      ));
      nextSample += stepM;
    }
    return pts;
  }

  /// Wind at a given downrange position [xM], from the configured wind zones.
  /// Falls back to [config.wind] if no zone covers x.
  Wind _windAt(double xM) {
    for (final z in config.windZones) {
      if (xM >= z.fromM && xM < z.toM) return z.wind;
    }
    return config.wind;
  }

  /// Interpolate the Drop Scale Factor at [rangeM] from the (range -> factor)
  /// map. Below the smallest key the first factor is used; above the largest
  /// key the last is used.
  double _dsfAt(double rangeM) {
    final dsf = config.dropScaleFactors;
    if (dsf.isEmpty) return 1.0;
    final keys = dsf.keys.toList()..sort();
    if (rangeM <= keys.first) return dsf[keys.first]!;
    if (rangeM >= keys.last) return dsf[keys.last]!;
    for (int i = 0; i < keys.length - 1; i++) {
      final r0 = keys[i], r1 = keys[i + 1];
      if (rangeM >= r0 && rangeM <= r1) {
        final f = (rangeM - r0) / (r1 - r0);
        return dsf[r0]! + f * (dsf[r1]! - dsf[r0]!);
      }
    }
    return 1.0;
  }

  /// Maximum level-flight range [m] for the current elevation, i.e. where the
  /// bullet path drops 2 m below the muzzle (a practical "max effective" proxy
  /// when no target height is given). Returns null if not found within range.
  double? maxEffectiveRange({double dropLimitM = 2.0, double scanToM = 3000}) {
    final elevation = solveZeroAngle();
    final raw = _integrate(stopRange: scanToM, elevation: elevation);
    for (final s in raw) {
      // bullet z relative to muzzle bore: z + sightHeight
      if (s.z + config.sightHeight <= -dropLimitM) return s.x;
    }
    return null;
  }

  /// Find the near and far zero crossings (where the path crosses the LOS,
  /// z=0), given the solved elevation. Returns ranges in meters.
  ({double? nearZero, double? farZero}) zeroCrossings(
      {double scanToM = 3000}) {
    final elevation = solveZeroAngle();
    final raw = _integrate(stopRange: scanToM, elevation: elevation);
    double? near, far;
    for (int i = 1; i < raw.length; i++) {
      final z0 = raw[i - 1].z;
      final z1 = raw[i].z;
      if (z0 == 0 && z1 == 0) continue;
      if ((z0 <= 0 && z1 > 0) || (z0 >= 0 && z1 < 0)) {
        final x = raw[i - 1].x +
            (raw[i].x - raw[i - 1].x) * (-z0) / (z1 - z0);
        if (near == null) {
          near = x;
        } else {
          far = x;
        }
      }
    }
    return (nearZero: near, farZero: far);
  }

  /// Drop (relative to LOS) at a given range [rangeM], with current config.
  double dropAtRange(double rangeM) {
    final elev = solveZeroAngle();
    final raw = _integrate(stopRange: rangeM, elevation: elev);
    if (raw.isEmpty) return 0;
    return raw.last.z;
  }

  /// Drop (m, relative to LOS) at a given range for a hypothetical BC.
  /// Used by the truing routine.
  double _dropAtRangeWithBc(double rangeM, double bc) {
    final alt = ShotConfig(
      muzzleVelocity: config.muzzleVelocity,
      mass: config.mass,
      diameter: config.diameter,
      bc: bc,
      dragModel: config.dragModel,
      sightHeight: config.sightHeight,
      zeroRange: config.zeroRange,
      atmosphere: config.atmosphere,
      wind: config.wind,
      coriolis: config.coriolis,
      spinDrift: false,
      twistIn: 0,
      lengthIn: 0,
      losAngleRad: config.losAngleRad,
    );
    return BallisticsSolver(alt, dt: dt).dropAtRange(rangeM);
  }

  /// Truing: given an observed drop [observedDropM] (relative to LOS, negative
  /// = bullet low) at [rangeM], find the BC that reproduces it. Returns the
  /// trued BC, or null if the solver can't match it within a sane BC band.
  /// (Lower BC -> more drop; higher BC -> less drop.)
  double? truedBc({required double rangeM, required double observedDropM}) {
    double lo = config.bc * 0.4;
    double hi = config.bc * 2.0;
    double fLo = _dropAtRangeWithBc(rangeM, lo) - observedDropM;
    double fHi = _dropAtRangeWithBc(rangeM, hi) - observedDropM;
    // Lower BC => more negative drop => fLo (drop - obs) more negative.
    // We need a sign change in f.
    if ((fLo > 0) == (fHi > 0)) return null; // observed drop out of band
    for (int i = 0; i < 60; i++) {
      final mid = 0.5 * (lo + hi);
      final fMid = _dropAtRangeWithBc(rangeM, mid) - observedDropM;
      if ((fLo > 0) != (fMid > 0)) {
        hi = mid;
        fHi = fMid;
      } else {
        lo = mid;
        fLo = fMid;
      }
    }
    return 0.5 * (lo + hi);
  }

  /// Muzzle-Velocity truing: given an observed drop [observedDropM] (relative
  /// to LOS, negative = bullet low) at [rangeM], find the muzzle velocity [m/s]
  /// that reproduces it. This is the most common field truing method because
  /// BC labels are often inaccurate and vary by lot. Higher MV -> less drop.
  /// Returns the trued MV, or null if not matchable within ±25%.
  double? truedMv({required double rangeM, required double observedDropM}) {
    double dropAtMv(double mvMs) {
      final alt = ShotConfig(
        muzzleVelocity: mvMs,
        mass: config.mass,
        diameter: config.diameter,
        bc: config.bc,
        dragModel: config.dragModel,
        sightHeight: config.sightHeight,
        zeroRange: config.zeroRange,
        atmosphere: config.atmosphere,
        wind: Wind.calm(),
        spinDrift: false,
        twistIn: 0,
        lengthIn: 0,
        losAngleRad: config.losAngleRad,
      );
      return BallisticsSolver(alt, dt: dt).dropAtRange(rangeM);
    }

    final base = config.muzzleVelocity;
    double lo = base * 0.75, hi = base * 1.25;
    double fLo = dropAtMv(lo) - observedDropM;
    double fHi = dropAtMv(hi) - observedDropM;
    if ((fLo > 0) == (fHi > 0)) return null; // out of band
    for (int i = 0; i < 60; i++) {
      final mid = 0.5 * (lo + hi);
      final fMid = dropAtMv(mid) - observedDropM;
      if ((fLo > 0) != (fMid > 0)) {
        hi = mid;
        fHi = fMid;
      } else {
        lo = mid;
        fLo = fMid;
      }
    }
    return 0.5 * (lo + hi);
  }

  ///
  /// factor = observedDrop / modelDrop  (both relative to LOS). A factor >1
  /// means the bullet drops more than the model predicts (model underestimates
  /// drop).
  Map<double, double> computeDsf(Map<double, double> observedDropsM) {
    final out = <double, double>{};
    for (final entry in observedDropsM.entries) {
      final rangeM = entry.key;
      final observed = entry.value;
      final model = dropAtRange(rangeM);
      if (model.abs() > 1e-6) {
        out[rangeM] = observed / model;
      }
    }
    return out;
  }

  /// Lead (hold-off) for a moving target, in meters of horizontal displacement
  /// the shooter must hold ahead of the target.
  ///
  /// [targetSpeedMps] target speed perpendicular to the line of sight (m/s).
  /// [rangeM] target distance.
  /// Returns the linear lead distance: lead = targetSpeed * timeOfFlight,
  /// where the time of flight is taken from the solved trajectory at [rangeM].
  double? leadAt({required double targetSpeedMps, required double rangeM}) {
    final elev = solveZeroAngle();
    final raw = _integrate(stopRange: rangeM, elevation: elev);
    if (raw.isEmpty) return null;
    final tof = (raw.length - 1) * dt;
    return targetSpeedMps * tof;
  }

  /// Convert a linear lead (meters) to an angular hold-off (radians) at range.
  static double leadToAngle(double leadM, double rangeM) =>
      rangeM > 0 ? leadM / rangeM : 0;

  /// Aerodynamic jump: the vertical deflection caused by a crosswind as the
  /// bullet transitions through transonic flow. Litz approximate form:
  ///
  ///   jump_MOA ≈ -0.01 * Sg * (drift_MOA)
  ///
  /// i.e. a right crosswind (drift right) pushes the impact slightly down for
  /// a right-hand twist. Returns the vertical correction in radians (+ = up).
  /// [driftRad] is the horizontal wind drift angle at the target (rad, +right).
  /// [sg] is the Miller stability factor.
  double aerodynamicJump({required double driftRad, required double sg}) {
    final driftMoa = driftRad * 60 * 180 / pi;
    final jumpMoa = -0.01 * sg * driftMoa;
    return jumpMoa * pi / (60 * 180);
  }

  /// Distance [m] at which the bullet's speed first drops below Mach 1.2
  /// (start of the transonic transition). Returns null if it stays supersonic
  /// within the scan range. Useful for warning the shooter that accuracy may
  /// degrade beyond this range.
  double? transonicRange({double machThreshold = 1.2, double scanToM = 3000}) {
    final elev = solveZeroAngle();
    final raw = _integrate(stopRange: scanToM, elevation: elev);
    final cSound = config.atmosphere.speedOfSound;
    final limit = machThreshold * cSound;
    double? prevSpeed;
    double? prevX;
    for (final s in raw) {
      final sp = sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz);
      if (sp <= limit) {
        if (prevSpeed != null && prevX != null && prevSpeed > limit) {
          // interpolate crossing
          final frac = (prevSpeed - limit) / (prevSpeed - sp);
          return prevX + frac * (s.x - prevX);
        }
        return s.x;
      }
      prevSpeed = sp;
      prevX = s.x;
    }
    return null;
  }

  /// Maximum Point Blank Range (MPBR): the farthest distance at which a hunter
  /// can aim dead-center and stay within ±[vitalRadiusM] of the point of aim,
  /// with no elevation knob dialing. Standard definition: fire the bullet with
  /// the smallest elevation that makes the trajectory apex just touch
  /// +vitalRadiusM (the high edge of the vital zone); MPBR ends where the
  /// bullet falls below -vitalRadiusM (the low edge).
  ///
  /// We integrate from the bore line (z = 0, sight height ignored) since MPBR
  /// is a bore-referenced concept. The optimal elevation is found by bisection:
  /// too low -> apex < +vital (more range possible); too high -> apex exceeds
  /// +vital (band violated). Returns the MPBR in meters, the apex height and
  /// its downrange position.
  ({double mpbrM, double apexM, double apexAtM}) maxPointBlankRange({
    double vitalRadiusM = 0.15, // ~6 inches
    double scanToM = 2000,
  }) {
    if (scanToM <= 0 || vitalRadiusM <= 0) {
      return (mpbrM: 0, apexM: 0, apexAtM: 0);
    }
    // Solver with bore-line reference, elevation controlled externally.
    BallisticsSolver altSolver() => BallisticsSolver(
          ShotConfig(
            muzzleVelocity: config.muzzleVelocity,
            mass: config.mass,
            diameter: config.diameter,
            bc: config.bc,
            dragModel: config.dragModel,
            sightHeight: 0, // bore-line reference
            zeroRange: 0,
            elevationOverride: 0, // always fire at explicit elevation below
            atmosphere: config.atmosphere,
            wind: Wind.calm(),
            spinDrift: false,
            losAngleRad: 0,
          ),
          dt: dt,
        );

    // Given elevation, compute apex height and the range where z falls below
    // -vital after the apex.
    (double apex, double apexAt, double mpbr) sim(double elev) {
      final raw =
          altSolver()._integrate(stopRange: scanToM, elevation: elev);
      double apex = -1e18, apexAt = 0;
      for (final s in raw) {
        if (s.z > apex) {
          apex = s.z;
          apexAt = s.x;
        }
      }
      double mpbr = scanToM;
      for (final s in raw) {
        if (s.x >= apexAt && s.z <= -vitalRadiusM) {
          mpbr = s.x;
          break;
        }
      }
      return (apex, apexAt, mpbr);
    }

    // Bisect elevation so apex == +vitalRadiusM (maximize MPBR).
    double lo = 0.0, hi = 0.15; // ~8.6 degrees upper bound
    var loRes = sim(lo);
    var hiRes = sim(hi);
    if (hiRes.$1 < vitalRadiusM) {
      // Even max elevation can't reach the band top; use max elevation.
      return (mpbrM: hiRes.$3, apexM: hiRes.$1, apexAtM: hiRes.$2);
    }
    for (int i = 0; i < 60; i++) {
      final mid = 0.5 * (lo + hi);
      final midRes = sim(mid);
      if (midRes.$1 < vitalRadiusM) {
        lo = mid;
        loRes = midRes;
      } else {
        hi = mid;
        hiRes = midRes;
      }
    }
    final best = 0.5 * (lo + hi);
    final res = sim(best);
    return (mpbrM: res.$3, apexM: res.$1, apexAtM: res.$2);
  }
}
