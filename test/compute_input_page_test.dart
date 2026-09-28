import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ballistics_calculator/models/firearm.dart';
import 'package:ballistics_calculator/services/database_service.dart';
import 'package:ballistics_calculator/ui/app_state.dart';
import 'package:ballistics_calculator/ui/compute_input_page.dart';

/// Regression coverage for the numeric text fields on the compute input page.
///
/// The controllers used to be created inside build(), so ANY setState (slider
/// drag, switch toggle) recreated them and silently wiped what the user was
/// typing. These tests pin the fix: typed values must survive rebuilds and
/// land in AppState.
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
    state.selectCartridge(const Cartridge(
      id: 'ct-test',
      designation: 'Test .308',
      manufacturer: 'ACME',
      caliber: '.308 Win',
      muzzleVelocityFps: 2600,
      refBarrelLengthIn: 24,
      bulletId: 'bt-test',
    ));
    state.selectBullet(const Bullet(
      id: 'bt-test',
      manufacturer: 'ACME',
      model: 'MatchKing',
      caliber: '.308 Win',
      massGr: 168,
      diameterIn: 0.308,
      lengthIn: 1.21,
      bcG1: 0.462,
      bcG7: 0.223,
      type: BulletType.hpbt,
    ));
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ComputeInputPage(state: state)));
    await tester.pump();
  }

  /// Temporary diagnostics: show what actually rendered when finders come up
  /// empty (printed to the CI log).
  void dumpTree(WidgetTester tester, String tag) {
    debugPrint('DUMP[$tag] exception=${tester.takeException()}');
    debugPrint('DUMP[$tag] page=${find.byType(ComputeInputPage).evaluate().length} '
        'scaffold=${find.byType(Scaffold).evaluate().length} '
        'listview=${find.byType(ListView).evaluate().length} '
        'textField=${find.byType(TextField).evaluate().length} '
        'text=${find.byType(Text).evaluate().length}');
    final texts = tester.widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '<span>')
        .take(50)
        .toList();
    debugPrint('DUMP[$tag] TEXTS(${texts.length}): ${texts.join(' | ')}');
  }

  testWidgets('typed chrono velocity survives a full page rebuild',
      (tester) async {
    await pumpPage(tester);
    dumpTree(tester, 'chrono');

    final field = find.widgetWithText(TextField, '测速仪初速 (fps, 0=用标称)');
    expect(field, findsOneWidget);
    await tester.enterText(field, '2650');
    await tester.pump();

    // Trigger the same rebuild path a slider drag or switch toggle uses.
    await tester.ensureVisible(find.text('启用科里奥利修正'));
    await tester.tap(find.text('启用科里奥利修正'));
    await tester.pump();

    expect(find.text('2650'), findsOneWidget);
    expect(state.chronoVelocityFps, 2650);
  });

  testWidgets('zero-atmosphere fields keep input across rebuilds',
      (tester) async {
    await pumpPage(tester);

    await tester.ensureVisible(find.text('归零大气修正'));
    await tester.tap(find.text('归零大气修正'));
    await tester.pump();

    final zeroTemp = find.widgetWithText(TextField, '归零温度°C');
    expect(zeroTemp, findsOneWidget);
    await tester.enterText(zeroTemp, '8.5');
    await tester.pump();

    await tester.ensureVisible(find.text('启用科里奥利修正'));
    await tester.tap(find.text('启用科里奥利修正'));
    await tester.pump();

    expect(find.text('8.5'), findsOneWidget);
    expect(state.zeroTempC, 8.5);
  });

  testWidgets('G7 suggestion appears only for bullets with a G7 BC',
      (tester) async {
    await pumpPage(tester);
    // test bullet has bcG7 and default model is G1 -> hint shown
    expect(find.textContaining('建议用 G7'), findsOneWidget);

    // accept the suggestion -> hint disappears
    await tester.tap(find.text('切换'));
    await tester.pump();
    expect(find.textContaining('建议用 G7'), findsNothing);
    expect(state.dragModelId, 'G7');
  });
}
