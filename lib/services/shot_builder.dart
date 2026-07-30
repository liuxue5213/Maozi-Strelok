import '../models/firearm.dart';
import '../models/modification.dart';
import '../physics/atmosphere.dart';
import '../physics/drag_models.dart';
import '../physics/stability.dart';
import '../physics/units.dart' as U;
import '../physics/ballistics_solver.dart';

/// Assembles a [ShotConfig] from a Firearm + Cartridge + Bullet + Modification
/// + environment, applying the physical corrections implied by the mods.
///
/// This is the bridge between the database layer and the physics engine.
class ShotBuilder {
  ShotBuilder._();

  /// Empirical muzzle-velocity change per inch of barrel length [fps/inch].
  /// Rifles ~ 25 fps/inch (typical rule of thumb); smaller for pistol calibers.
  static double mvPerInchFor(String caliber) {
    final c = caliber.toLowerCase();
    if (c.contains('9x19') ||
        c.contains('9mm') ||
        c.contains('.45') ||
        c.contains('9x18') ||
        c.contains('mak')) {
      return 10; // pistol: smaller effect
    }
    if (c.contains('12 ga') || c.contains('12ga')) return 8;
    if (c.contains('.50') || c.contains('12.7')) return 20;
    return 25; // rifle default
  }

  /// Recompute muzzle velocity from the reference barrel length to the
  /// effective (possibly modified) barrel length, then apply the muzzle-device
  /// factor.
  static double effectiveMuzzleVelocity({
    required Cartridge cartridge,
    required double effectiveBarrelIn,
    required double refBarrelIn,
    required MuzzleDevice device,
  }) {
    final base = cartridge.muzzleVelocityFps;
    final delta = (effectiveBarrelIn - refBarrelIn) * mvPerInchFor(cartridge.caliber);
    return (base + delta) * device.velocityFactor;
  }

  /// Build the solver config.
  static ShotConfig build({
    required Firearm firearm,
    required Cartridge cartridge,
    required Bullet bullet,
    required Modification mod,
    required Atmosphere atmosphere,
    required Wind wind,
    Coriolis? coriolis,
    String dragModelId = 'G1',
    bool spinDrift = true,
    double losAngleDeg = 0,
    double chronoVelocityFps = 0,
    double powderTempF = 0, // temp at chrono time (0 = feature off)
    double mvTempSensitivityFpsPerF = 0, // fps change per °F
    double cantAngleDeg = 0,
    Map<double, double> dropScaleFactors = const {},
  }) {
    // Chronograph override takes precedence; otherwise compute from barrel
    // length + muzzle device.
    final effBarrel = mod.effectiveBarrelLength(firearm);
    var mvFps = chronoVelocityFps > 0
        ? chronoVelocityFps
        : effectiveMuzzleVelocity(
            cartridge: cartridge,
            effectiveBarrelIn: effBarrel,
            refBarrelIn: cartridge.refBarrelLengthIn,
            device: mod.muzzleDevice,
          );
    // Powder temperature sensitivity: adjust MV for the difference between the
    // current ambient temperature and the temperature at chrono time.
    if (powderTempF != 0 && mvTempSensitivityFpsPerF != 0) {
      final currentTempF = U.Units.cToF(atmosphere.temperatureC);
      mvFps += (currentTempF - powderTempF) * mvTempSensitivityFpsPerF;
      if (mvFps < 0) mvFps = 0;
    }
    final drag = resolveDragModel(dragModelId);
    final bc = dragModelId == 'G7' ? (bullet.bcG7 ?? bullet.bcG1) : bullet.bcG1;

    return ShotConfig(
      muzzleVelocity: U.Units.fpsToMps(mvFps),
      mass: U.Units.grainToKg(bullet.massGr),
      diameter: U.Units.inchToM(bullet.diameterIn),
      bc: bc,
      dragModel: drag,
      sightHeight: U.Units.inchToM(mod.effectiveSightHeight(firearm)),
      zeroRange: U.Units.yardsToM(mod.zeroRangeYd),
      atmosphere: atmosphere,
      wind: wind,
      coriolis: coriolis,
      spinDrift: spinDrift,
      twistIn: mod.effectiveTwistRate(firearm),
      lengthIn: bullet.lengthIn,
      losAngleRad: losAngleDeg * 3.141592653589793 / 180.0,
      cantAngleRad: cantAngleDeg * 3.141592653589793 / 180.0,
      dropScaleFactors: dropScaleFactors,
    );
  }

  /// Miller stability for this bullet + barrel/twist + atmosphere.
  static double stabilityFactor({
    required Bullet bullet,
    required Firearm firearm,
    required Modification mod,
    required Atmosphere atmosphere,
    required Cartridge cartridge,
  }) {
    final effBarrel = mod.effectiveBarrelLength(firearm);
    final mvFps = effectiveMuzzleVelocity(
      cartridge: cartridge,
      effectiveBarrelIn: effBarrel,
      refBarrelIn: cartridge.refBarrelLengthIn,
      device: mod.muzzleDevice,
    );
    return Stability.millerSg(
      massGr: bullet.massGr,
      diaIn: bullet.diameterIn,
      lenIn: bullet.lengthIn,
      twistIn: mod.effectiveTwistRate(firearm),
      v0fps: mvFps,
      airDensityKgM3: atmosphere.density,
    );
  }
}
