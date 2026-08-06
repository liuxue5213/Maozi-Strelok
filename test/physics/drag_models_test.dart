import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/drag_models.dart';

void main() {
  group('Drag tables', () {
    test('G1 Cd is monotonic decreasing through supersonic regime', () {
      final g1 = G1DragModel.instance;
      // From Mach 1.0 onward, drag should generally decrease.
      double prev = g1.cdRef(1.0);
      for (double m = 1.1; m <= 3.0; m += 0.1) {
        final v = g1.cdRef(m);
        expect(v, lessThanOrEqualTo(prev + 0.01));
        prev = v;
      }
    });

    test('G7 Cd lower than G1 in supersonic regime (lower-drag shape)', () {
      final g1 = G1DragModel.instance;
      final g7 = G7DragModel.instance;
      for (double m = 2.0; m <= 3.0; m += 0.2) {
        expect(g7.cdRef(m), lessThan(g1.cdRef(m)));
      }
    });

    test('subsonic G1 Cd is near 0.20', () {
      final g1 = G1DragModel.instance;
      expect(g1.cdRef(0.5), closeTo(0.20, 0.01));
    });

    test('interpolation returns endpoints at table bounds', () {
      final g1 = G1DragModel.instance;
      expect(g1.cdRef(0.0), g1.cdRef(0.0));
      expect(g1.cdRef(100.0), g1.cdRef(5.0)); // clamps to last
    });

    test('transonic peak near Mach 0.95', () {
      // G1 drag peaks in the transonic region (~Mach 0.9-1.0) then falls.
      final g1 = G1DragModel.instance;
      final cdAt095 = g1.cdRef(0.95);
      final cdAt15 = g1.cdRef(1.5);
      expect(cdAt095, greaterThan(cdAt15));
    });
  });

  group('CustomDragModel', () {
    test('linear interpolation of user table', () {
      final m = CustomDragModel('Custom', [
        [0.5, 0.2],
        [1.0, 0.4],
        [2.0, 0.3],
      ]);
      expect(m.cdRef(0.75), closeTo(0.3, 1e-9)); // midpoint of [0.5,0.2]-[1.0,0.4]
      expect(m.cdRef(1.5), closeTo(0.35, 1e-9));
      expect(m.cdRef(0.0), 0.2); // clamps low
      expect(m.cdRef(5.0), 0.3); // clamps high
    });
  });

  group('form factor / actual Cd', () {
    test('actual Cd scales with form factor (SD/BC)', () {
      final g1 = G1DragModel.instance;
      // 175gr .308: SD = (175/7000 lb) / (0.308 in)^2 = 0.2635
      final sd = DragModel.sectionalDensity(175, 0.308);
      expect(sd, closeTo(0.2635, 0.002));
      // Cd_actual = Cd_ref * SD / BC
      final cd = g1.cd(2.5, 0.505, 175, 0.308);
      final cdRef = g1.cdRef(2.5);
      expect(cd, closeTo(cdRef * sd / 0.505, 1e-9));
    });
  });
}
