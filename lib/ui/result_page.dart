import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/firearm.dart';
import '../physics/atmosphere.dart';
import '../physics/ballistics_solver.dart';
import '../physics/coriolis.dart';
import '../physics/units.dart' as U;
import '../services/shot_builder.dart';
import '../services/dope_card.dart';
import 'app_state.dart';
import 'format.dart';
import 'reticle_page.dart';

class ResultPage extends StatefulWidget {
  final AppState state;
  const ResultPage({super.key, required this.state});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  List<TrajectoryPoint>? _traj;
  double? _sg;
  double? _nearZero;
  double? _farZero;
  double? _maxRange;
  double? _transonicM;
  double? _leadM; // linear lead at max range for moving target
  ShotConfig? _cfg;
  String? _error;
  bool _showMoa = true; // toggle MOA <-> MIL for corrections

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
        spinDrift: s.useSpinDrift,
        losAngleDeg: s.losAngleDeg,
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
      final zeros = solver.zeroCrossings();
      final transonic = solver.transonicRange();
      // Lead at the max range for the moving-target speed.
      double? lead;
      if (s.targetSpeedMph > 0) {
        final targetMps = U.Units.mphToMps(s.targetSpeedMph);
        lead = solver.leadAt(
            targetSpeedMps: targetMps,
            rangeM: U.Units.yardsToM(s.maxRangeYd));
      }
      setState(() {
        _cfg = cfg;
        _traj = traj;
        _sg = sg;
        _nearZero = zeros.nearZero;
        _farZero = zeros.farZero;
        _maxRange = solver.maxEffectiveRange();
        _transonicM = transonic;
        _leadM = lead;
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
    if (traj == null || traj.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('结果')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bullet = widget.state.bullet!;
    final ct = widget.state.cartridge!;
    final last = traj.last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('弹道结果'),
        actions: [
          IconButton(
            tooltip: '分划板模拟',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ReticlePage(state: widget.state, traj: traj),
              ),
            ),
            icon: const Icon(Icons.center_focus_strong),
          ),
          IconButton(
            tooltip: '导出 DOPE 卡',
            onPressed: () => _showDope(context, bullet, ct, traj, sys),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: _showMoa ? '切换 MIL' : '切换 MOA',
            onPressed: () => setState(() => _showMoa = !_showMoa),
            icon: Icon(_showMoa ? Icons.architecture : Icons.straighten),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Loadout summary
          Card(
            child: ListTile(
              leading: const Icon(Icons.gps_fixed),
              title: Text('${widget.state.firearm!.name} · ${ct.designation}'),
              subtitle: Text(
                  '${bullet.manufacturer} ${bullet.model} · ${bullet.massGr}gr · BC ${widget.state.useG7 ? (bullet.bcG7 ?? bullet.bcG1).toStringAsFixed(3) : bullet.bcG1.toStringAsFixed(3)} (${widget.state.useG7 ? 'G7' : 'G1'})'),
            ),
          ),
          // Stability + key results grid
          _keyResultsCard(bullet, sys),
          const SizedBox(height: 8),
          Text('弹道曲线（超高 drop vs 距离）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(height: 220, child: _dropChart(traj, sys)),
          const SizedBox(height: 8),
          Text('剩余速度（vs 距离）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(height: 160, child: _velocityChart(traj, sys)),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('数据表', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text('修正: ${_showMoa ? 'MOA' : 'MIL'}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          _dataTable(traj, sys),
        ],
      ),
    );
  }

  Widget _keyResultsCard(Bullet bullet, U.UnitSystem sys) {
    final muzzleV = _cfg != null ? _cfg!.muzzleVelocity : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // stability banner
            if (_sg != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _sgColor(_sg!).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    '陀螺稳定性 Sg = ${_sg!.toStringAsFixed(2)} · ${_sgAssess(_sg!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            // Transonic warning
            if (_transonicM != null &&
                _transonicM! < U.Units.yardsToM(widget.state.maxRangeYd)) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    '⚠ 弹丸在 ${(_transonicM! * 1.09361).toStringAsFixed(0)}yd '
                    '(${_transonicM!.toStringAsFixed(0)}m) 进入跨音速区，'
                    '此后精度可能下降',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
            // Moving-target lead
            if (_leadM != null && _leadM! > 0) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    '🎯 移动目标提前量 @${widget.state.maxRangeYd.toStringAsFixed(0)}yd: '
                    '${(_leadM! * (_showMoa ? 0 : 39.37)).toStringAsFixed(1)}${_showMoa ? '' : 'in'}'
                    '${_showMoa ? '约 ${(U.Units.radToMil(_leadM! / U.Units.yardsToM(widget.state.maxRangeYd))).toStringAsFixed(1)} MIL' : ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 2.2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                _stat('初速', Fmt.velocity(muzzleV, sys)),
                _stat('归零距离',
                    '${widget.state.mod.zeroRangeYd.toStringAsFixed(0)} yd'),
                _stat('近零点', _nearZero == null
                    ? '-'
                    : '${(_nearZero! * 1.09361).toStringAsFixed(0)} yd'),
                _stat('远零点', _farZero == null
                    ? '-'
                    : '${(_farZero! * 1.09361).toStringAsFixed(0)} yd'),
                _stat('最大有效射程', _maxRange == null
                    ? '-'
                    : '${(_maxRange! * 1.09361).toStringAsFixed(0)} yd'),
                _stat('末速', Fmt.velocity(_traj!.last.speed, sys)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Color _sgColor(double sg) {
    if (sg < 1.0) return Colors.red;
    if (sg < 1.3) return Colors.orange;
    return Colors.green;
  }

  Widget _dropChart(List<TrajectoryPoint> traj, U.UnitSystem sys) {
    final toX = (double m) =>
        sys == U.UnitSystem.imperial ? m * 1.09361 : m;
    final toY = (double m) =>
        sys == U.UnitSystem.imperial ? m * 39.37 : m * 100;
    final spots = traj.map((p) => FlSpot(toX(p.range), toY(p.drop))).toList();
    final xs = spots.map((e) => e.x).toList()..sort();
    final ys = spots.map((e) => e.y).toList()..sort();
    // zero (LOS) reference line
    double minX = 0, maxX = xs.last * 1.05;
    double minY = (ys.first * 1.1).floorToDouble();
    double maxY = (ys.last * 1.1).ceilToDouble();
    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      minX: minX,
      maxX: maxX,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(
          color: v == 0 ? Colors.green : Colors.grey.withValues(alpha: 0.3),
          strokeWidth: v == 0 ? 1.5 : 1,
        ),
        checkToShowHorizontalLine: (v) =>
            v == 0 || v == minY || v == maxY,
      ),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(y: 0, color: Colors.green, strokeWidth: 1.5),
      ]),
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
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
    final toX = (double m) =>
        sys == U.UnitSystem.imperial ? m * 1.09361 : m;
    final toY = (double m) =>
        sys == U.UnitSystem.imperial ? m * 3.28084 : m;
    final spots = traj.map((p) => FlSpot(toX(p.range), toY(p.speed))).toList();
    final xs = spots.map((e) => e.x).toList()..sort();
    // Mach 1 reference (speed of sound ~ 340 m/s / 1115 fps)
    final mach1y = sys == U.UnitSystem.imperial ? 1115.0 : 340.0;
    return LineChart(LineChartData(
      minY: 0,
      minX: 0,
      maxX: xs.last * 1.05,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
            y: mach1y,
            color: Colors.red,
            strokeWidth: 1,
            dashArray: [4, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: const TextStyle(fontSize: 10, color: Colors.red),
              labelResolver: (_) => 'Mach 1',
            )),
      ]),
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
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
            DataColumn(label: Text('高低修正')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? '风偏(in)' : '风偏(cm)')),
            DataColumn(label: Text('风向修正')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'vel(fps)' : 'vel(m/s)')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'E(ftlb)' : 'E(J)')),
            DataColumn(label: const Text('t(s)')),
          ],
          rows: traj
              .map((p) => DataRow(cells: [
                    DataCell(Text(Fmt.dist(p.range, sys))),
                    DataCell(Text(Fmt.shortLen(p.drop, sys))),
                    DataCell(Text(p.range > 1
                        ? Fmt.comeUp(p.comeUpRad, moa: _showMoa)
                        : '-')),
                    DataCell(Text(Fmt.shortLen(p.windage, sys))),
                    DataCell(Text(p.range > 1
                        ? _windageCorrection(p, sys)
                        : '-')),
                    DataCell(Text(Fmt.velocity(p.speed, sys))),
                    DataCell(Text(Fmt.energy(p.energy, sys))),
                    DataCell(Text(Fmt.time(p.timeOfFlight))),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  /// Windage angular correction (same magnitude formula as come-up, but for
  /// the horizontal windage offset). Sign: + = push right.
  String _windageCorrection(TrajectoryPoint p, U.UnitSystem sys) {
    final rad = p.windage / p.range; // small angle
    final sign = rad >= 0 ? '+' : '';
    final val = _showMoa ? U.Units.radToMoa(rad.abs()) : U.Units.radToMil(rad.abs());
    return '$sign${val.toStringAsFixed(1)} ${_showMoa ? 'MOA' : 'MIL'}';
  }

  /// Show the DOPE card in a copyable dialog.
  void _showDope(BuildContext context, Bullet bullet, Cartridge ct,
      List<TrajectoryPoint> traj, U.UnitSystem sys) {
    final s = widget.state;
    final loadout = '${s.firearm!.name} | ${ct.designation} | '
        '${bullet.manufacturer} ${bullet.model} ${bullet.massGr}gr | '
        'BC ${s.useG7 ? (bullet.bcG7 ?? bullet.bcG1) : bullet.bcG1} (${s.useG7 ? 'G7' : 'G1'}) | '
        '归零 ${s.mod.zeroRangeYd.toStringAsFixed(0)}yd';
    final conditions =
        '${s.temperatureC.toStringAsFixed(0)}°C / ${s.pressureHpa.toStringAsFixed(0)}hPa / '
        '海拔${s.altitudeM.toStringAsFixed(0)}m / 风${s.windSpeedMph.toStringAsFixed(0)}mph@${s.windDirectionDeg.toStringAsFixed(0)}°';
    final text = DopeCard.build(
      loadout: loadout,
      traj: traj,
      sys: sys,
      moa: _showMoa,
      conditions: conditions,
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('DOPE 卡'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
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
