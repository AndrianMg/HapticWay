import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';

void main() {
  group('constants', () {
    test('haptic k default is within slider range', () {
      expect(kHapticConstantK, greaterThanOrEqualTo(0.1));
      expect(kHapticConstantK, lessThanOrEqualTo(2.0));
    });

    test('distance bounds are positive and ordered', () {
      expect(kMinDistanceMeters, greaterThan(0));
      expect(kMaxDistanceMeters, greaterThan(kMinDistanceMeters));
    });
  });
}
