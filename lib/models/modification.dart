import 'firearm.dart';

/// User-customizable modifications to a firearm, which feed into the solver.
///
/// These are the three dimensions selected in the plan:
///  1. Barrel / twist rate -> recompute muzzle velocity & Miller stability.
///  2. Optics / zero       -> sight height & zero range affect drop/windage.
///  3. Muzzle device       -> small muzzle-velocity correction.
class Modification {
  /// Custom barrel length [in]. null = use firearm default.
  final double? barrelLengthIn;

  /// Custom twist rate [in/turn]. null = use firearm default.
  final double? twistRateIn;

  /// Sight/optic height above bore [in].
  final double sightHeightIn;

  /// Zero range [yd].
  final double zeroRangeYd;

  /// Muzzle device type (affects MV correction & flags).
  final MuzzleDevice muzzleDevice;

  const Modification({
    this.barrelLengthIn,
    this.twistRateIn,
    this.sightHeightIn = 1.5,
    this.zeroRangeYd = 100,
    this.muzzleDevice = MuzzleDevice.none,
  });

  Modification copyWith({
    double? barrelLengthIn,
    double? twistRateIn,
    double? sightHeightIn,
    double? zeroRangeYd,
    MuzzleDevice? muzzleDevice,
  }) =>
      Modification(
        barrelLengthIn: barrelLengthIn ?? this.barrelLengthIn,
        twistRateIn: twistRateIn ?? this.twistRateIn,
        sightHeightIn: sightHeightIn ?? this.sightHeightIn,
        zeroRangeYd: zeroRangeYd ?? this.zeroRangeYd,
        muzzleDevice: muzzleDevice ?? this.muzzleDevice,
      );

  /// Effective barrel length for this firearm after modifications.
  double effectiveBarrelLength(Firearm f) =>
      barrelLengthIn ?? f.barrelLengthIn;

  /// Effective twist rate after modifications.
  double effectiveTwistRate(Firearm f) => twistRateIn ?? f.twistRateIn;

  /// Effective sight height.
  double effectiveSightHeight(Firearm f) => sightHeightIn;

  factory Modification.fromJson(Map<String, dynamic> j) => Modification(
        barrelLengthIn: (j['barrelLengthIn'] as num?)?.toDouble(),
        twistRateIn: (j['twistRateIn'] as num?)?.toDouble(),
        sightHeightIn: (j['sightHeightIn'] as num?)?.toDouble() ?? 1.5,
        zeroRangeYd: (j['zeroRangeYd'] as num?)?.toDouble() ?? 100,
        muzzleDevice: MuzzleDevice.values
            .byName(j['muzzleDevice'] as String? ?? 'none'),
      );

  Map<String, dynamic> toJson() => {
        if (barrelLengthIn != null) 'barrelLengthIn': barrelLengthIn,
        if (twistRateIn != null) 'twistRateIn': twistRateIn,
        'sightHeightIn': sightHeightIn,
        'zeroRangeYd': zeroRangeYd,
        'muzzleDevice': muzzleDevice.name,
      };
}

/// Muzzle device, each giving a small muzzle-velocity correction factor.
enum MuzzleDevice {
  none, // 无装置（裸口）
  flashHider, // 消焰器
  muzzleBrake, // 制退器
  compensator, // 补偿器
  suppressor, // 消音器（一般略增 MV）
  linearComp, // 直喷补偿器
}

/// Velocity multiplier applied to nominal MV for a given muzzle device.
/// These are conservative empirical factors (most are ~1.0; suppressors often
/// add a little MV, brakes/hiders essentially neutral).
extension MuzzleDeviceVelocity on MuzzleDevice {
  double get velocityFactor => switch (this) {
        MuzzleDevice.none => 1.0,
        MuzzleDevice.flashHider => 1.0,
        MuzzleDevice.muzzleBrake => 1.0,
        MuzzleDevice.compensator => 1.0,
        MuzzleDevice.suppressor => 1.015, // ~+1.5% typical
        MuzzleDevice.linearComp => 1.0,
      };
}
