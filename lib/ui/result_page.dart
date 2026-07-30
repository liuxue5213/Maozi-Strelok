import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../physics/atmosphere.dart';
import '../physics/ballistics_solver.dart';
import '../physics/coriolis.dart';
import '../physics/units.dart' as U;
import '../services/shot_builder.dart';
import 'app_state.dart';
import 'format.dart';

class ResultPage extends StatefulWidget {
  final AppState state;
  const ResultPage({super.key, required this.state});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  List<TrajectoryPoint>? _traj;
  double? _sg;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  void _compute() {
    try {
      final s = widget.state;
      final f = s.firearm!;
      final ct = s.cartridge!;
      final b = s.bullet!;
      final atmo = Atmosphere(
        temperatureC: s.temperatureC,
        pressurePa: U.Units.hpaToPa(s.pressureHpa),
        relativeHumidity: s.relativeHumidity,
        altitudeM: s.altitudeM,
      );
      final wind = Wind(
        speedMs: U.Units.mphToMps(s.windSpeedMph),
        directionDeg: s.windDirectionDeg,
      );
      final cor = s.useCoriolis
          ? Coriolis(
              latitudeDeg: s.latitudeDeg,
              azimuthDeg: s.azimuthDeg,
              gravity: atmo.gravity,
            )
          : null;
      final cfg = ShotBuilder.build(
        firearm: f,
        cartridge: ct,
        bullet: b,
        mod: s.mod,
        atmosphere: atmo,
        wind: wind,
        coriolis: cor,
        dragModelId: s.useG7 ? 'G7' : 'G1',
      );
      final solver = BallisticsSolver(cfg);
      final traj = solver.solve(
        maxRangeM: U.Units.yardsToM(s.maxRangeYd),
        stepM: U.Units.yardsToM(s.stepYd),
      );
      final sg = ShotBuilder.stabilityFactor(
        firearm: f,
        cartridge: ct,
        bullet: b,
        mod: s.mod,
        atmosphere: atmo,
      );
      setState(() {
        _traj = traj;
        _sg = sg;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final sys = widget.state.unitSystem;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('结果')),
        body: Center(child: Text('计算出错：$_error')),
      );
    }
    final traj = _traj;
    if (traj == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('结果')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bullet = widget.state.bullet!;
    final ct = widget.state.cartridge!;
    return Scaffold(
      appBar: AppBar(title: const Text('弹道结果')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              title: Text('${widget.state.firearm!.name} · ${ct.designation}'),
              subtitle: Text(
                  '${bullet.manufacturer} ${bullet.model} · ${bullet.massGr}gr · BC ${widget.state.useG7 ? (bullet.bcG7 ?? bullet.bcG1) : bullet.bcG1}'),
            ),
          ),
          if (_sg != null)
            Card(
              color: _sg! < 1.0
                  ? Colors.red.withValues(alpha: 0.15)
                  : (_sg! < 1.3 ? Colors.orange.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15)),
              child: ListTile(
                leading: const Icon(Icons.timeline),
                title: Text('陀螺稳定性 Sg = ${_sg!.toStringAsFixed(2)}'),
                subtitle: Text(_sgAssess(_sg!)),
              ),
            ),
          const SizedBox(height: 8),
          Text('弹道曲线（超高 drop vs 距离）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _dropChart(traj, sys),
          ),
          const SizedBox(height: 8),
          Text('剩余速度（vs 距离）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: _velocityChart(traj, sys),
          ),
          const SizedBox(height: 12),
          Text('数据表', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _dataTable(traj, sys),
        ],
      ),
    );
  }

  Widget _dropChart(List<TrajectoryPoint> traj, U.UnitSystem sys) {
    final spots = traj
        .map((p) => FlSpot(
            sys == U.UnitSystem.imperial ? p.range * 1.09361 : p.range,
            sys == U.UnitSystem.imperial ? p.drop * 39.37 : p.drop * 100))
        .toList();
    final xs = spots.map((e) => e.x).toList()..sort();
    final ys = spots.map((e) => e.y).toList()..sort();
    return LineChart(LineChartData(
      minY: (ys.first * 1.1).floorToDouble(),
      maxY: (ys.last * 1.1).ceilToDouble(),
      minX: 0,
      maxX: xs.last * 1.05,
      gridData: FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}'))),
        leftTitles: AxisTitles(
          axisNameWidget: Text(sys == U.UnitSystem.imperial ? 'in' : 'cm'),
          sideTitles: SideTitles(showTitles: true, reservedSize: 36),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.blue,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],
    ));
  }

  Widget _velocityChart(List<TrajectoryPoint> traj, U.UnitSystem sys) {
    final spots = traj
        .map((p) => FlSpot(
            sys == U.UnitSystem.imperial ? p.range * 1.09361 : p.range,
            sys == U.UnitSystem.imperial ? p.speed * 3.28084 : p.speed))
        .toList();
    final xs = spots.map((e) => e.x).toList()..sort();
    return LineChart(LineChartData(
      minY: 0,
      minX: 0,
      maxX: xs.last * 1.05,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}'))),
        leftTitles: AxisTitles(
          axisNameWidget: Text(sys == U.UnitSystem.imperial ? 'fps' : 'm/s'),
          sideTitles: SideTitles(showTitles: true, reservedSize: 36),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.orange,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }

  Widget _dataTable(List<TrajectoryPoint> traj, U.UnitSystem sys) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          columns: [
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'yd' : 'm')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'drop(in)' : 'drop(cm)')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'wind(in)' : 'wind(cm)')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'vel(fps)' : 'vel(m/s)')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'E(ftlb)' : 'E(J)')),
            DataColumn(label: const Text('t(s)')),
          ],
          rows: traj
              .map((p) => DataRow(cells: [
                    DataCell(Text(Fmt.dist(p.range, sys))),
                    DataCell(Text(Fmt.shortLen(p.drop, sys))),
                    DataCell(Text(Fmt.shortLen(p.windage, sys))),
                    DataCell(Text(Fmt.velocity(p.speed, sys))),
                    DataCell(Text(Fmt.energy(p.energy, sys))),
                    DataCell(Text(Fmt.time(p.timeOfFlight))),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  String _sgAssess(double sg) {
    if (sg < 1.0) return '不稳定！弹丸可能翻滚';
    if (sg < 1.3) return '临界，建议更换更快的缠距';
    if (sg < 1.5) return '稳定';
    return '最佳';
  }
}
