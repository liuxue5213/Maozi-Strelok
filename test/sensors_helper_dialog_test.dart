import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ballistics_calculator/models/firearm.dart';
import 'package:ballistics_calculator/services/database_service.dart';
import 'package:ballistics_calculator/ui/app_state.dart';
import 'package:ballistics_calculator/ui/sensors_helper_dialog.dart';

import 'pump_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = DatabaseService();
    state = AppState(db);
    state.selectFirearm(const Firearm(
      id: 'test-rifle',
      name: 'Test Rifle',
      manufacturer: 'ACME',
      country: 'USA',
      category: FirearmCategory.boltRifle,
      roles: [FirearmRole.civilian],
      compatibleCalibers: ['.308 Win'],
      barrelLengthIn: 24,
      twistRateIn: 10,
      sightHeightIn: 1.7,
      defaultCartridgeId: 'ct-test',
      yearIntroduced: 2000,
    ));
  });

  testWidgets('dialog applies manual lat/azimuth/LOS values to the state',
      (tester) async {
    await pumpTallPage(tester, SensorsHelperDialog(state: state));

    final lat = find.widgetWithText(TextField, '纬度 (°, +北 / -南)');
    final az = find.widgetWithText(TextField, '射击方位角 (°, 北=0 顺时针)');
    final los = find.widgetWithText(TextField, '射击仰俯角 (°, +上 / -下)');
    expect(lat, findsOneWidget);
    expect(az, findsOneWidget);
    expect(los, findsOneWidget);

    await tester.enterText(lat, '39.9');
    await tester.enterText(az, '315');
    await tester.enterText(los, '-5');
    await tester.tap(find.text('应用'));
    await tester.pump();

    expect(state.latitudeDeg, 39.9);
    expect(state.azimuthDeg, 315);
    expect(state.losAngleDeg, -5);
  });

  testWidgets('coriolis switch toggles in the dialog', (tester) async {
    await pumpTallPage(tester, SensorsHelperDialog(state: state));
    expect(state.useCoriolis, isFalse);

    await tester.tap(find.text('启用科里奥利/Eötvös'));
    await tester.pump();
    expect(state.useCoriolis, isTrue);
  });
}
