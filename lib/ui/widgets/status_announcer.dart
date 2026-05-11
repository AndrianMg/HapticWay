import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

class StatusAnnouncer {
  static DateTime? _lastAnnouncement;
  static String? _lastLabel;

  static void announce(String label) {
    final now = DateTime.now();
    if (_lastLabel == label && _lastAnnouncement != null) {
      final elapsed = now.difference(_lastAnnouncement!);
      if (elapsed.inMilliseconds < 1500) return;
    }
    _lastLabel = label;
    _lastAnnouncement = now;
    SemanticsService.sendAnnouncement(
      WidgetsBinding.instance.platformDispatcher.views.first,
      label,
      TextDirection.ltr,
    );
  }

  static void reset() {
    _lastLabel = null;
    _lastAnnouncement = null;
  }
}
