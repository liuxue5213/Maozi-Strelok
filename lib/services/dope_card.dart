import '../physics/ballistics_solver.dart';
import '../physics/units.dart' as U;

/// Generates a plain-text DOPE (Data On Previous Engagements) card from a
/// solved trajectory, suitable for sharing / printing.
class DopeCard {
  DopeCard._();

  /// Build a DOPE card string. [loadout] is a short description of the
  /// gun/ammo/bullet, [correctionAngle] selects MOA or MIL.
  static String build({
    required String loadout,
    required List<TrajectoryPoint> traj,
    required U.UnitSystem sys,
    required bool moa,
    String? conditions,
  }) {
    final buf = StringBuffer();
    buf.writeln('===== DOPE 卡 =====');
    buf.writeln(loadout);
    if (conditions != null && conditions.isNotEmpty) {
      buf.writeln(conditions);
    }
    buf.writeln('-----------------------------');
    final distH = sys == U.UnitSystem.imperial ? 'yd' : 'm';
    final dropH = sys == U.UnitSystem.imperial ? 'drop(in)' : 'drop(cm)';
    final windH = sys == U.UnitSystem.imperial ? 'wind(in)' : 'wind(cm)';
    final velH = sys == U.UnitSystem.imperial ? 'vel(fps)' : 'vel(m/s)';
    final ang = moa ? '修正(MOA)' : '修正(MIL)';
    buf.writeln('${distH.padRight(8)}${dropH.padRight(10)}${ang.padRight(12)}'
        '${windH.padRight(10)}${velH.padRight(10)}t(s)');
    buf.writeln('-----------------------------');
    for (final p in traj) {
      final dist = sys == U.UnitSystem.imperial
          ? (p.range * 1.09361).toStringAsFixed(0)
          : p.range.toStringAsFixed(0);
      final drop = sys == U.UnitSystem.imperial
          ? (p.drop * 39.37).toStringAsFixed(1)
          : (p.drop * 100).toStringAsFixed(1);
      final wind = sys == U.UnitSystem.imperial
          ? (p.windage * 39.37).toStringAsFixed(1)
          : (p.windage * 100).toStringAsFixed(1);
      final vel = sys == U.UnitSystem.imperial
          ? (p.speed * 3.28084).toStringAsFixed(0)
          : p.speed.toStringAsFixed(0);
      final angVal = moa
          ? U.Units.radToMoa(p.comeUpRad.abs()).toStringAsFixed(1)
          : U.Units.radToMil(p.comeUpRad.abs()).toStringAsFixed(1);
      buf.writeln('${dist.padRight(8)}'
          '${drop.padRight(10)}'
          '${(p.range > 1 ? angVal : '-').padRight(12)}'
          '${wind.padRight(10)}'
          '${vel.padRight(10)}'
          '${p.timeOfFlight.toStringAsFixed(2)}');
    }
    buf.writeln('=============================');
    return buf.toString();
  }

  /// Build a CSV (comma-separated) trajectory table for spreadsheet import.
  /// Columns match the on-screen table; values follow the chosen unit system.
  static String toCsv({
    required List<TrajectoryPoint> traj,
    required U.UnitSystem sys,
  }) {
    final b = StringBuffer();
    final distH = sys == U.UnitSystem.imperial ? 'range_yd' : 'range_m';
    final dropH = sys == U.UnitSystem.imperial ? 'drop_in' : 'drop_cm';
    final windH = sys == U.UnitSystem.imperial ? 'wind_in' : 'wind_cm';
    final velH = sys == U.UnitSystem.imperial ? 'vel_fps' : 'vel_mps';
    final eH = sys == U.UnitSystem.imperial ? 'energy_ftlbf' : 'energy_J';
    b.writeln('$distH,$dropH,comeUp_MOA,$windH,wind_MOA,$velH,$eH,tof_s');
    for (final p in traj) {
      final dist = sys == U.UnitSystem.imperial
          ? (p.range * 1.09361)
          : p.range;
      final drop = sys == U.UnitSystem.imperial
          ? (p.drop * 39.3701)
          : (p.drop * 100);
      final wind = sys == U.UnitSystem.imperial
          ? (p.windage * 39.3701)
          : (p.windage * 100);
      final vel = sys == U.UnitSystem.imperial
          ? (p.speed * 3.28084)
          : p.speed;
      final e = sys == U.UnitSystem.imperial
          ? (p.energy / 1.3558179483314)
          : p.energy;
      final comeMoa = p.range > 1 ? U.Units.radToMoa(p.comeUpRad.abs()) : 0.0;
      final windMoa = p.range > 1
          ? U.Units.radToMoa((p.windage / p.range).abs())
          : 0.0;
      b.writeln('${_fmt(dist)},${_fmt(drop)},${_fmt(comeMoa)},'
          '${_fmt(wind)},${_fmt(windMoa)},${_fmt(vel)},${_fmt(e)},'
          '${p.timeOfFlight.toStringAsFixed(3)}');
    }
    return b.toString();
  }

  static String _fmt(double v) {
    if (v.abs() < 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(1);
  }
}
