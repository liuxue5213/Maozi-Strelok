import 'dart:math';
import 'units.dart';

/// Coriolis / Eötvös acceleration contribution due to Earth's rotation.
///
/// We work in a local "shooting" frame at the firing point:
///   x  -> downrange (bore axis direction, in the horizontal plane)
///   y  -> left/right (cross-range; +y = right)
///   z  -> up
///
/// Earth's angular velocity vector Omega is decomposed into this local frame
/// from the shooter's latitude and the firing azimuth (bearing, clockwise from
/// North). The Coriolis acceleration is then  a = -2 * Omega x v.
///
/// The vertical (Eötvös) term is also produced automatically by this cross
/// product — firing East reduces apparent gravity (bullet drops less), firing
/// West increases it.
class Coriolis {
  /// Earth angular velocity [rad/s].
  static const double earthOmega = 7.2921159e-5;

  /// Firing point latitude [degrees], +North.
  final double latitudeDeg;

  /// Firing azimuth / bearing [degrees], clockwise from true North.
  final double azimuthDeg;

  /// Earth gravity at the firing point [m/s^2] (for the vertical component).
  final double gravity;

  Coriolis({
    required this.latitudeDeg,
    required this.azimuthDeg,
    required this.gravity,
  });

  bool get isEnabled => latitudeDeg.abs() > 1e-6;

  /// Components of Earth's angular-velocity vector in the shooting frame:
  ///   OmegaX (downrange), OmegaY (cross-range), OmegaZ (vertical up).
  /// Derived from latitude `lat` and azimuth `az` (measured CW from North).
  ({double ox, double oy, double oz}) get omegaComponents {
    final lat = Units.degToRad(latitudeDeg);
    final az = Units.degToRad(azimuthDeg);
    // In local frame (x=downrange along bearing, y=right, z=up):
    //   Omega = earthOmega * ( cos(lat)*cos(az),  cos(lat)*sin(az)... )
    // Standard decomposition:
    //   Ox =  Omega * cos(lat) * cos(az)
    //   Oy = -Omega * cos(lat) * sin(az)   (left positive convention handled)
    //   Oz =  Omega * sin(lat)
    final ox = earthOmega * cos(lat) * cos(az);
    final oy = earthOmega * cos(lat) * sin(az);
    final oz = earthOmega * sin(lat);
    return (ox: ox, oy: oy, oz: oz);
  }

  /// Coriolis acceleration [m/s^2] for velocity (vx, vy, vz).
  /// a = -2 * Omega x v
  ({double ax, double ay, double az}) acceleration(
      double vx, double vy, double vz) {
    if (!isEnabled) return (ax: 0, ay: 0, az: 0);
    final o = omegaComponents;
    // cross product Omega x v
    final cx = o.oy * vz - o.oz * vy;
    final cy = o.oz * vx - o.ox * vz;
    final cz = o.ox * vy - o.oy * vx;
    return (ax: -2 * cx, ay: -2 * cy, az: -2 * cz);
  }
}
