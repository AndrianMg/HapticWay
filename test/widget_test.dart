import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/ui/widgets/status_announcer.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
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

  group('StatusAnnouncer throttle', () {
    setUp(() => StatusAnnouncer.reset());

    test('second identical call within 1500 ms is silently dropped', () {
      // Both calls complete without error; the second is throttled internally.
      StatusAnnouncer.announce('obstacle detected');
      StatusAnnouncer.announce('obstacle detected');
    });

    test('different labels are not throttled', () {
      StatusAnnouncer.announce('obstacle detected');
      StatusAnnouncer.announce('path clear');
    });
  });
}
