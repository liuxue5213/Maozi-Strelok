import '../physics/units.dart' as U;

/// Helpers for formatting values in either metric or imperial, for display.
class Fmt {
  Fmt._();

  /// Distance: m or yd.
  static String dist(double m, U.UnitSystem sys) {
    if (sys == U.UnitSystem.imperial) {
      return '${(m * 1.09361).toStringAsFixed(0)} yd';
    }
    return '${m.toStringAsFixed(0)} m';
  }

  /// Short drop/height: cm or in.
  static String shortLen(double m, U.UnitSystem sys) {
    if (sys == U.UnitSystem.imperial) {
      return '${(m * 39.3701).toStringAsFixed(1)} in';
    }
    return '${(m * 100).toStringAsFixed(1)} cm';
  }

  /// Velocity: m/s or fps.
  static String velocity(double mps, U.UnitSystem sys) {
    if (sys == U.UnitSystem.imperial) {
      return '${(mps * 3.28084).toStringAsFixed(0)} fps';
    }
    return '${mps.toStringAsFixed(0)} m/s';
  }

  /// Energy: J or ft-lbf.
  static String energy(double j, U.UnitSystem sys) {
    if (sys == U.UnitSystem.imperial) {
      return '${(j / 1.3558179483314).toStringAsFixed(0)} ft-lbf';
    }
    return '${j.toStringAsFixed(0)} J';
  }

  static String time(double s) => '${s.toStringAsFixed(2)} s';

  /// Angular correction: MOA or MIL.
  static String comeUp(double rad, {bool moa = true}) {
    if (moa) {
      return '${U.Units.radToMoa(rad).toStringAsFixed(1)} MOA';
    }
    return '${U.Units.radToMil(rad).toStringAsFixed(1)} MIL';
  }
}
