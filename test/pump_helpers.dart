import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ListView builds children lazily even when given an explicit children list,
/// so on the default 800x600 test surface everything below the fold is absent
/// from the widget tree and finders return nothing. Give the page a very tall
/// viewport so the whole body builds.
Future<void> pumpTallPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(600, 20000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}
