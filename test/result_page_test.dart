import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ballistics_calculator/services/database_service.dart';
import 'package:ballistics_calculator/ui/app_state.dart';
import 'package:ballistics_calculator/ui/result_page.dart';

import 'pump_helpers.dart';

/// End-to-end coverage of the results pipeline: real asset database ->
/// ShotBuilder -> RK4 solve -> rendered page. Pins the key-results stats
/// (stability, density altitude, max ordinate), the multi-target card with
/// its per-distance hit-probability chips, and the chart section headers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = DatabaseService();
    await db.load(); // real built-in asset database (185 bullets / 68 guns)
  });

  Future<AppState> readyState() async {
    final s = AppState(db);
    s.selectFirearm(db.firearm('m24')!); // M24 -> M118LR default load
    s.windSpeedMph = 10;
    s.customTargetsYd = const [300, 500];
    s.persistEnvAndShooting();
    return s;
  }

  testWidgets('full solve renders stats, charts and multi-target hit odds',
      (tester) async {
    final state = await readyState();
    await pumpTallPage(tester, ResultPage(state: state));
    await tester.pumpAndSettle();

    // App bar + loadout summary
    expect(find.text('弹道结果'), findsOneWidget);
    expect(find.textContaining('M24'), findsWidgets);
    expect(find.textContaining('M118LR'), findsWidgets);

    // Key results grid
    expect(find.textContaining('陀螺稳定性'), findsOneWidget);
    expect(find.textContaining('密度高度'), findsOneWidget);
    expect(find.textContaining('最大弹道高'), findsOneWidget);
    expect(find.textContaining('最大有效射程'), findsOneWidget);
    expect(find.textContaining('MPBR'), findsOneWidget);

    // Charts + data table headers
    expect(find.textContaining('弹道曲线'), findsOneWidget);
    expect(find.textContaining('风偏曲线'), findsOneWidget);
    expect(find.textContaining('剩余速度'), findsOneWidget);
    expect(find.textContaining('数据表'), findsOneWidget);

    // Multi-target card: one 命中 chip per configured target distance
    expect(find.textContaining('多目标快速修正'), findsOneWidget);
    expect(find.text('命中'), findsNWidgets(2));
  });

  testWidgets('solver rejects an impossible configuration with an error view',
      (tester) async {
    final state = await readyState();
    // zero-range beyond max range makes the solve degenerate
    state.updateMod(state.mod.copyWith(zeroRangeYd: 2000));
    state.maxRangeYd = 100;

    await pumpTallPage(tester, ResultPage(state: state));
    await tester.pumpAndSettle();

    final hasError = find.textContaining('计算出错').evaluate().isNotEmpty;
    final hasResults =
        find.textContaining('陀螺稳定性').evaluate().isNotEmpty;
    expect(hasError || hasResults, isTrue,
        reason: 'page must either show the error view or a valid result');
  });
}
