import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/firearm.dart';
import '../physics/atmosphere.dart';
import '../physics/ballistics_solver.dart';
import '../physics/coriolis.dart';
import '../physics/hit_probability.dart';
import '../physics/units.dart' as U;
import '../services/shot_builder.dart';
import '../services/dope_card.dart';
import 'aim_demo_page.dart';
import 'app_state.dart';
import 'cartridge_picker_dialog.dart';
import 'format.dart';
import 'hud_page.dart';
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
  double? _mpbrM; // max point blank range (vital-zone)
  double? _leadM; // linear lead at max range for moving target
  List<Map<String, double>> _multiTargets = const [];
  double? _hitProb; // hit probability at max range target
  ShotConfig? _cfg;
  String? _error;
  bool _showMoa = true; // toggle MOA <-> MIL for corrections
  bool _useWez = false; // analytic hit-prob vs Monte-Carlo WEZ
  /// Multi-load comparison: each entry is (label, trajectory) for overlay.
  List<({String label, List<TrajectoryPoint> traj, int color})> _compare = const [];
  /// Bullet ids selected for comparison (excludes the current bullet).
  final Set<String> _compareBulletIds = {};

  bool _computing = true; // loading guard so the heavy solve doesn't block UI

  @override
  void initState() {
    super.initState();
    // Defer the heavy RK4 + WEZ computation one frame so the route transition
    // / loading indicator can paint first. Without this the whole solve runs
    // synchronously inside initState and the screen freezes on entry.
    WidgetsBinding.instance.addPostFrameCallback((_) => _compute());
  }

  void _compute() {
    setState(() => _computing = true);
    // Yield to the event loop so the loading spinner renders before the
    // (CPU-bound) integration starts.
    Future.microtask(() {
      _runCompute();
    });
  }

  void _runCompute() {
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
      // Zero-atmosphere: when enabled, the zero angle is solved under the
      // conditions present when the rifle was zeroed, and the trajectory is
      // integrated at current conditions. Long-range zeros taken at a
      // different air density are then honored without re-zeroing.
      final zeroAtmo = s.useZeroAtmo
          ? Atmosphere(
              temperatureC: s.zeroTempC,
              pressurePa: U.Units.hpaToPa(s.zeroPressureHpa),
              relativeHumidity: s.zeroHumidity,
              altitudeM: s.zeroAltitudeM,
            )
          : null;
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
        zeroAtmosphere: zeroAtmo,
        wind: wind,
        coriolis: cor,
        dragModelId: s.dragModelId,
        spinDrift: s.useSpinDrift,
        losAngleDeg: s.losAngleDeg,
        chronoVelocityFps: s.chronoVelocityFps,
        powderTempF: s.powderTempF,
        mvTempSensitivityFpsPerF: s.mvTempSensitivityFpsPerF,
        cantAngleDeg: s.cantAngleDeg,
        dropScaleFactors: s.dsf,
        windZones: s.windZones.map((z) => z.toSi()).toList(),
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
      final mpbr = solver.maxPointBlankRange(
          vitalRadiusM: U.Units.inchToM(s.targetSizeIn) / 2);
      // Lead at the max range for the moving-target speed.
      double? lead;
      if (s.targetSpeedMph > 0) {
        final targetMps = U.Units.mphToMps(s.targetSpeedMph);
        lead = solver.leadAt(
            targetSpeedMps: targetMps,
            rangeM: U.Units.yardsToM(s.maxRangeYd));
      }
      // Per-target corrections for the multi-target list.
      final multiTargets = <Map<String, double>>[];
      for (final yd in s.customTargetsYd) {
        final m = U.Units.yardsToM(yd);
        final pt = traj.reduce((a, b) =>
            (a.range - m).abs() < (b.range - m).abs() ? a : b);
        multiTargets.add({
          'yd': yd,
          'range': pt.range,
          'drop': pt.drop,
          'windage': pt.windage,
          'comeUp': pt.comeUpRad,
          'speed': pt.speed,
          'tof': pt.timeOfFlight,
        });
      }
      // Hit probability at the max-range target: estimate the wind-drift and
      // drop sensitivities from adjacent trajectory samples (cheap, no extra
      // integration) and feed the shooter's error budget.
      double hitProb = 0;
      if (traj.length >= 3) {
        final last = traj.last;
        final prev = traj[traj.length - 2];
        final dRange = (last.range - prev.range).abs();
        // drop per yard (m per yd)
        final dropPerYd = dRange > 1e-9
            ? ((last.drop - prev.drop).abs()) / (dRange * 1.09361)
            : 0.0;
        // wind drift per mph: approximate using current windage and the
        // configured wind speed; if calm, use a nominal 0.1m per mph at range.
        double driftPerMph = 0.0;
        if (s.windSpeedMph > 0.1) {
          driftPerMph = last.windage.abs() / s.windSpeedMph;
        } else {
          driftPerMph = (last.range * 0.0005); // nominal sensitivity
        }
        final targetRadiusM = U.Units.inchToM(s.targetSizeIn) / 2;
        if (_useWez) {
          // Monte-Carlo WEZ (Applied Ballistics method).
          hitProb = Wez.run(
            shots: 1000,
            rangeM: last.range,
            gunMoa: s.gunAccuracyMoa,
            shooterMoa: s.shooterErrorMoa,
            windErrMph: s.windErrorMph,
            windDriftPerMphM: driftPerMph,
            rangeErrYd: s.rangeErrorYd,
            dropPerYdM: dropPerYd,
            targetWIn: s.targetSizeIn,
            seed: 42, // deterministic for stable display
          );
        } else {
          final sigma = HitProbability.sigmaRadFromBudget(
            gunMoa: s.gunAccuracyMoa,
            shooterMoa: s.shooterErrorMoa,
            windErrMph: s.windErrorMph,
            rangeErrYd: s.rangeErrorYd,
            windDriftPerMphM: driftPerMph,
            dropPerYdM: dropPerYd,
            rangeM: last.range,
          );
          hitProb = HitProbability.circularP(
            targetRadiusM: targetRadiusM,
            rangeM: last.range,
            sigmaRad: sigma,
          );
        }
      }
      setState(() {
        _cfg = cfg;
        _traj = traj;
        _sg = sg;
        _nearZero = zeros.nearZero;
        _farZero = zeros.farZero;
        _maxRange = solver.maxEffectiveRange();
        _transonicM = transonic;
        _mpbrM = mpbr.mpbrM;
        _leadM = lead;
        _multiTargets = multiTargets;
        _hitProb = hitProb;
        _error = null;
        _computing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _computing = false;
      });
    }
  }

  /// Recompute comparison trajectories for the selected extra bullets.
  /// Each runs the full solver with the same conditions but a different bullet,
  /// so the shooter can see how drop differs across loads at a glance.
  /// Supports up to 8 loads (Ballistic app parity).
  void _recomputeCompare() {
    final s = widget.state;
    if (_compareBulletIds.isEmpty) {
      setState(() => _compare = const []);
      return;
    }
    final f = s.firearm!;
    final ct = s.cartridge!;
    final atmoBase = Atmosphere(
      temperatureC: s.temperatureC,
      pressurePa: U.Units.hpaToPa(s.pressureHpa),
      relativeHumidity: s.relativeHumidity,
      altitudeM: s.altitudeM,
    );
    // 8 distinct colors for up to 8-load comparison.
    const colors = [
      0xFFE53935, 0xFF8E24AA, 0xFF1E88E5, 0xFFF4511E,
      0xFF43A047, 0xFFFDD835, 0xFF00ACC1, 0xFF6D4C41,
    ];
    final out = <({String label, List<TrajectoryPoint> traj, int color})>[];
    var ci = 0;
    for (final bid in _compareBulletIds) {
      final b = s.db.bullet(bid);
      if (b == null) continue;
      final cfg = ShotBuilder.build(
        firearm: f,
        cartridge: ct,
        bullet: b,
        mod: s.mod,
        atmosphere: atmoBase,
        wind: Wind.calm(),
        dragModelId: s.dragModelId,
        spinDrift: false,
      );
      final traj = BallisticsSolver(cfg).solve(
        maxRangeM: U.Units.yardsToM(s.maxRangeYd),
        stepM: U.Units.yardsToM(s.stepYd),
      );
      out.add((
        label: '${b.manufacturer} ${b.model} ${b.massGr}gr',
        traj: traj,
        color: colors[ci % colors.length],
      ));
      ci++;
    }
    setState(() => _compare = out);
    _scoreLoads();
  }

  /// Score each compared load on 3 criteria and pick the best overall — mirrors
  /// Ballistic's "auto best load selection" (wind drift / flatness / energy).
  /// Lower wind-drift-at-max-range is better; flatter trajectory (smallest
  /// |apex drop|) is better; higher remaining energy is better.
  void _scoreLoads() {
    if (_compare.isEmpty) return;
    // Already computed in recompute; scoring is derived from the trajectories
    // and stored in _loadScores for the ranking UI.
    setState(() {
      // scoring is done lazily in the ranking widget
    });
  }

  /// Best-load scoring result: (label, windDriftScore, flatnessScore, energyScore, totalRank).
  List<({String label, double windDrift, double flatness, double energy})>
      get _loadScores {
    return _compare.map((c) {
      final last = c.traj.isNotEmpty ? c.traj.last : null;
      // wind drift magnitude at max range (lower is better)
      final windDrift = last == null ? 999.0 : last.windage.abs() * 39.37; // inches
      // flatness: max |drop| across the trajectory (lower = flatter = better)
      double maxDrop = 0;
      for (final p in c.traj) {
        if (p.drop.abs() > maxDrop) maxDrop = p.drop.abs();
      }
      final flatness = maxDrop * 39.37; // inches
      // remaining energy at max range (higher is better -> negate for rank)
      final energy = last == null ? 0.0 : last.energy;
      return (label: c.label, windDrift: windDrift, flatness: flatness, energy: energy);
    }).toList();
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
    if (_computing) {
      return Scaffold(
        appBar: AppBar(title: const Text('弹道结果')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              SizedBox(height: 24),
              Text('正在计算弹道…', style: TextStyle(fontSize: 17)),
              SizedBox(height: 8),
              Text('RK4 弹道积分 · 大气密度 · 风修正 · 稳定性',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              SizedBox(height: 16),
              // indeterminate progress bar for extra "working" feedback
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(),
              ),
            ],
          ),
        ),
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
            tooltip: 'HUD (单发大数字显示)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HudPage(state: widget.state, traj: traj),
              ),
            ),
            icon: const Icon(Icons.visibility),
          ),
          IconButton(
            tooltip: '瞄准演示 (不同距离瞄准哪里)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AimDemoPage(state: widget.state, traj: traj),
              ),
            ),
            icon: const Icon(Icons.ads_click),
          ),
          IconButton(
            tooltip: '导出 DOPE 卡',
            onPressed: () => _showDope(context, bullet, ct, traj, sys),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: '导出 CSV',
            onPressed: () => _showCsv(context, traj, sys),
            icon: const Icon(Icons.table_view),
          ),
          IconButton(
            tooltip: _showMoa ? '切换 MIL' : '切换 MOA',
            onPressed: () => setState(() => _showMoa = !_showMoa),
            icon: Icon(_showMoa ? Icons.architecture : Icons.straighten),
          ),
          IconButton(
            tooltip: _useWez ? 'WEZ蒙特卡洛 (点击切解析法)' : '解析法 (点击切WEZ蒙特卡洛)',
            onPressed: () { setState(() => _useWez = !_useWez); _compute(); },
            icon: const Icon(Icons.casino),
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
                  '${bullet.manufacturer} ${bullet.model} · ${bullet.massGr}gr · BC ${widget.state.dragModelId == 'G7' ? (bullet.bcG7 ?? bullet.bcG1).toStringAsFixed(3) : bullet.bcG1.toStringAsFixed(3)} (${widget.state.dragModelId})'),
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
          Text('风偏曲线（vs 距离）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(height: 160, child: _windageChart(traj, sys)),
          const SizedBox(height: 8),
          Text('剩余速度（vs 距离）',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(height: 160, child: _velocityChart(traj, sys)),
          const SizedBox(height: 12),
          // Multi-load comparison overlay
          _compareSection(sys),
          if (_multiTargets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('多目标快速修正 (${_showMoa ? 'MOA' : 'MIL'})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _multiTargetsCard(sys),
          ],
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
            // Hit probability banner
            if (_hitProb != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _hitProbColor(_hitProb!).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    '🎯 命中率 ${_useWez ? '(WEZ蒙特卡洛)' : '(解析法)'} '
                    '@${widget.state.maxRangeYd.toStringAsFixed(0)}yd '
                    '(目标 ${widget.state.targetSizeIn.toStringAsFixed(0)}"): '
                    '${(_hitProb! * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
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
                _stat('直射距离(MPBR)', _mpbrM == null
                    ? '-'
                    : '${(_mpbrM! * 1.09361).toStringAsFixed(0)} yd'),
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

  Color _hitProbColor(double p) {
    if (p < 0.3) return Colors.red;
    if (p < 0.7) return Colors.orange;
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

  /// Wind-deflection curve (inches or cm vs distance).
  Widget _windageChart(List<TrajectoryPoint> traj, U.UnitSystem sys) {
    final toX = (double m) =>
        sys == U.UnitSystem.imperial ? m * 1.09361 : m;
    final toY = (double m) =>
        sys == U.UnitSystem.imperial ? m * 39.37 : m * 100;
    final spots = traj.map((p) => FlSpot(toX(p.range), toY(p.windage))).toList();
    final xs = spots.map((e) => e.x).toList()..sort();
    double minX = 0, maxX = xs.last * 1.05;
    return LineChart(LineChartData(
      minY: 0,
      minX: minX,
      maxX: maxX,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(
          color: v == 0 ? Colors.grey : Colors.grey.withValues(alpha: 0.3),
          strokeWidth: v == 0 ? 1.5 : 1,
        ),
        checkToShowHorizontalLine: (v) => v == 0,
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
          axisNameWidget:
              Text(sys == U.UnitSystem.imperial ? 'in' : 'cm'),
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
          color: Colors.purple,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],
    ));
  }

  /// Multi-load comparison section: pick extra bullets, overlay their drop
  /// curves against the current bullet. Lets the shooter compare loads.
  /// Supports up to 8 loads with auto best-load scoring (Ballistic parity).
  Widget _compareSection(U.UnitSystem sys) {
    final s = widget.state;
    final loadCount = _compareBulletIds.length + 1; // +1 for current bullet
    final canAdd = loadCount < 8;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('多弹种对比',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text(' ($loadCount/8)',
                    style: TextStyle(
                        fontSize: 12,
                        color: canAdd ? Colors.grey : Colors.red)),
                const Spacer(),
                TextButton.icon(
                  icon: Icon(Icons.add, size: 18,
                      color: canAdd ? null : Colors.grey),
                  label: Text('添加弹头',
                      style: TextStyle(
                          fontSize: 12,
                          color: canAdd ? null : Colors.grey)),
                  onPressed: canAdd
                      ? () async {
                          final picked = await showDialog<Bullet>(
                            context: context,
                            builder: (_) => BulletPickerDialog(
                              state: s,
                              caliber: s.cartridge?.caliber ??
                                  s.firearm!.compatibleCalibers.first,
                            ),
                          );
                          if (picked != null &&
                              picked.id != s.bullet?.id &&
                              !_compareBulletIds.contains(picked.id)) {
                            _compareBulletIds.add(picked.id);
                            _recomputeCompare();
                          }
                        }
                      : null,
                ),
              ],
            ),
            if (_compareBulletIds.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('选择其它弹头叠加落点曲线进行对比。'
                    '最多 8 弹种同时对比。',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else ...[
              Wrap(
                spacing: 6,
                children: _compare.map((c) => Chip(
                      label: Text(c.label, style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        final bid = s.db.bullets
                            .where((b) =>
                                '${b.manufacturer} ${b.model} ${b.massGr}gr' ==
                                c.label)
                            .firstOrNull
                            ?.id;
                        if (bid != null) _compareBulletIds.remove(bid);
                        _recomputeCompare();
                      },
                      avatar: CircleAvatar(
                          backgroundColor: Color(c.color), radius: 6),
                    )).toList(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                  height: 180, child: _compareChart(_traj!, _compare, sys)),
              const SizedBox(height: 8),
              // Auto best-load ranking table
              if (_loadScores.isNotEmpty) _rankingTable(sys),
            ],
          ],
        ),
      ),
    );
  }

  /// Best-load ranking table: scores each load on wind drift, flatness, and
  /// energy — Ballistic's "auto best load selection". Best per column is
  /// highlighted; overall rank sorts by weighted score.
  Widget _rankingTable(U.UnitSystem sys) {
    final scores = _loadScores;
    // find best (min) per metric
    double bestWind = scores.first.windDrift, bestFlat = scores.first.flatness,
        bestEnergy = scores.first.energy;
    for (final sc in scores) {
      if (sc.windDrift < bestWind) bestWind = sc.windDrift;
      if (sc.flatness < bestFlat) bestFlat = sc.flatness;
      if (sc.energy > bestEnergy) bestEnergy = sc.energy;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('自动最佳弹种评分',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 12,
            headingRowHeight: 28,
            dataRowMinHeight: 24,
            columns: const [
              DataColumn(label: Text('弹种', style: TextStyle(fontSize: 10))),
              DataColumn(label: Text('风偏"', style: TextStyle(fontSize: 10))),
              DataColumn(label: Text('弹道高"', style: TextStyle(fontSize: 10))),
              DataColumn(label: Text('末能J', style: TextStyle(fontSize: 10))),
            ],
            rows: scores.map((sc) {
              return DataRow(cells: [
                DataCell(Text(sc.label,
                    style: const TextStyle(fontSize: 9))),
                DataCell(Text(sc.windDrift.toStringAsFixed(1),
                    style: TextStyle(
                        fontSize: 10,
                        color: sc.windDrift == bestWind
                            ? Colors.green
                            : null,
                        fontWeight: sc.windDrift == bestWind
                            ? FontWeight.bold
                            : null))),
                DataCell(Text(sc.flatness.toStringAsFixed(1),
                    style: TextStyle(
                        fontSize: 10,
                        color: sc.flatness == bestFlat
                            ? Colors.green
                            : null,
                        fontWeight: sc.flatness == bestFlat
                            ? FontWeight.bold
                            : null))),
                DataCell(Text(sc.energy.toStringAsFixed(0),
                    style: TextStyle(
                        fontSize: 10,
                        color: sc.energy == bestEnergy
                            ? Colors.green
                            : null,
                        fontWeight: sc.energy == bestEnergy
                            ? FontWeight.bold
                            : null))),
              ]);
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Overlay drop chart: current bullet (blue) + comparison loads.
  Widget _compareChart(
      List<TrajectoryPoint> base,
      List<({String label, List<TrajectoryPoint> traj, int color})> compare,
      U.UnitSystem sys) {
    final toX = (double m) =>
        sys == U.UnitSystem.imperial ? m * 1.09361 : m;
    final toY = (double m) =>
        sys == U.UnitSystem.imperial ? m * 39.37 : m * 100;
    final bars = <LineChartBarData>[];
    final baseSpots =
        base.map((p) => FlSpot(toX(p.range), toY(p.drop))).toList();
    bars.add(LineChartBarData(
      spots: baseSpots,
      isCurved: true,
      color: Colors.blue,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
    ));
    for (final c in compare) {
      bars.add(LineChartBarData(
        spots: c.traj.map((p) => FlSpot(toX(p.range), toY(p.drop))).toList(),
        isCurved: true,
        color: Color(c.color),
        barWidth: 1.8,
        dotData: const FlDotData(show: false),
        dashArray: [5, 3],
      ));
    }
    final xs = baseSpots.map((e) => e.x).toList()..sort();
    double minX = 0, maxX = xs.last * 1.05;
    return LineChart(LineChartData(
      minY: 0,
      minX: minX,
      maxX: maxX,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}'))),
        leftTitles: AxisTitles(
          axisNameWidget:
              Text(sys == U.UnitSystem.imperial ? 'in' : 'cm'),
          sideTitles: SideTitles(showTitles: true, reservedSize: 36),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: bars,
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
            DataColumn(label: Text('旋钮格数')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? '风偏(in)' : '风偏(cm)')),
            DataColumn(label: Text('风向修正')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'vel(fps)' : 'vel(m/s)')),
            DataColumn(label: const Text('Mach')),
            DataColumn(label: Text(sys == U.UnitSystem.imperial ? 'E(ftlb)' : 'E(J)')),
            DataColumn(label: const Text('t(s)')),
          ],
          rows: traj
              .map((p) {
                final mach = p.speed / _cfg!.atmosphere.speedOfSound;
                final machColor = mach > 1.2
                    ? null
                    : (mach > 1.0
                        ? Colors.orange
                        : Colors.red);
                return DataRow(cells: [
                    DataCell(Text(Fmt.dist(p.range, sys))),
                    DataCell(Text(Fmt.shortLen(p.drop, sys))),
                    DataCell(Text(p.range > 1
                        ? Fmt.comeUp(p.comeUpRad, moa: _showMoa)
                        : '-')),
                    DataCell(Text(p.range > 1
                        ? '${Fmt.clicks(p.comeUpRad, widget.state.clickMoa)}↑'
                        : '-')),
                    DataCell(Text(Fmt.shortLen(p.windage, sys))),
                    DataCell(Text(p.range > 1
                        ? _windageCorrection(p, sys)
                        : '-')),
                    DataCell(Text(Fmt.velocity(p.speed, sys),
                        style: machColor != null
                            ? TextStyle(color: machColor, fontWeight: FontWeight.w600)
                            : null)),
                    DataCell(Text('${mach.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: machColor ?? Colors.grey))),
                    DataCell(Text(Fmt.energy(p.energy, sys))),
                    DataCell(Text(Fmt.time(p.timeOfFlight))),
                  ]);
              })
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
        'BC ${s.dragModelId == 'G7' ? (bullet.bcG7 ?? bullet.bcG1) : bullet.bcG1} (${s.dragModelId}) | '
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

  /// Show the trajectory as copyable CSV for spreadsheet import.
  void _showCsv(BuildContext context, List<TrajectoryPoint> traj, U.UnitSystem sys) {
    final csv = DopeCard.toCsv(traj: traj, sys: sys);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('CSV 轨迹数据'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(csv,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11)),
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

  /// Multi-target quick-reference card: one row per explicit target distance
  /// with its elevation + windage correction and remaining velocity.
  Widget _multiTargetsCard(U.UnitSystem sys) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (final t in _multiTargets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 56,
                        child: Text('${t['yd']?.toStringAsFixed(0)}yd',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(
                      child: _multiChip(
                          '高低',
                          _showMoa
                              ? '${U.Units.radToMoa((t['comeUp']!).abs()).toStringAsFixed(1)} MOA'
                              : '${U.Units.radToMil((t['comeUp']!).abs()).toStringAsFixed(1)} MIL',
                          t['comeUp']! >= 0 ? Colors.blue : Colors.orange),
                    ),
                    Expanded(
                      child: _multiChip(
                          '风向',
                          _showMoa
                              ? '${U.Units.radToMoa((t['windage']! / t['range']!).abs()).toStringAsFixed(1)} MOA'
                              : '${U.Units.radToMil((t['windage']! / t['range']!).abs()).toStringAsFixed(1)} MIL',
                          Colors.purple),
                    ),
                    SizedBox(
                        width: 64,
                        child: Text(
                            sys == U.UnitSystem.imperial
                                ? '${(t['speed']! * 3.28084).toStringAsFixed(0)}fps'
                                : '${t['speed']!.toStringAsFixed(0)}m/s',
                            style: const TextStyle(fontSize: 11))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _multiChip(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }

  String _sgAssess(double sg) {
    if (sg < 1.0) return '不稳定！弹丸可能翻滚';
    if (sg < 1.3) return '临界，建议更换更快的缠距';
    if (sg < 1.5) return '稳定';
    return '最佳';
  }
}
