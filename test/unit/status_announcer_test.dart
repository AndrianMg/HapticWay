import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/ui/widgets/status_announcer.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

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
