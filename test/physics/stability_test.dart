import 'package:flutter_test/flutter_test.dart';
import 'package:ballistics_calculator/physics/stability.dart';

void main() {
  group('Miller stability', () {
    // Classic reference: 175gr .308, 1:12" twist, 2700fps, ~1.2" long bullet.
    // Published Sg for this combo is ~1.3-1.5 at sea level.
    test('175gr .308 at 1:12 gives stable value', () {
      final sg = Stability.millerSg(
        massGr: 175,
        diaIn: 0.308,
        lenIn: 1.2,
        twistIn: 12,
        v0fps: 2700,
      );
      expect(sg, greaterThan(1.0));
      expect(sg, lessThan(2.0));
    });

    test('faster twist (smaller inches/turn) increases Sg', () {
      final slow = Stability.millerSg(
        massGr: 175,
        diaIn: 0.308,
        lenIn: 1.2,
        twistIn: 14,
        v0fps: 2700,
      );
      final fast = Stability.millerSg(
        massGr: 175,
        diaIn: 0.308,
        lenIn: 1.2,
        twistIn: 8,
        v0fps: 2700,
      );
      expect(fast, greaterThan(slow));
    });

    test('heavier / longer bullet is less stable', () {
      final light = Stability.millerSg(
        massGr: 150,
        diaIn: 0.308,
        lenIn: 1.0,
        twistIn: 12,
        v0fps: 2700,
      );
      final heavy = Stability.millerSg(
        massGr: 220,
        diaIn: 0.308,
        lenIn: 1.4,
        twistIn: 12,
        v0fps: 2700,
      );
      expect(heavy, lessThan(light));
    });

    test('lower air density (altitude) increases Sg', () {
      final sea = Stability.millerSg(
        massGr: 175,
        diaIn: 0.308,
        lenIn: 1.2,
        twistIn: 12,
        v0fps: 2700,
        airDensityKgM3: 1.225,
      );
      final high = Stability.millerSg(
        massGr: 175,
        diaIn: 0.308,
        lenIn: 1.2,
        twistIn: 12,
        v0fps: 2700,
        airDensityKgM3: 0.9,
      );
      expect(high, greaterThan(sea));
    });

    test('assessment labels', () {
      expect(Stability.assess(0.8).toLowerCase(), contains('unstable'));
      expect(Stability.assess(1.2).toLowerCase(), contains('marginal'));
      expect(Stability.assess(1.4).toLowerCase(), contains('stable'));
      expect(Stability.assess(2.0).toLowerCase(), contains('optimal'));
    });
  });
}
