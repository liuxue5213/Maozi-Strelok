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
}
