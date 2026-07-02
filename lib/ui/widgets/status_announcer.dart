import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

class StatusAnnouncer {
  static DateTime? _lastAnnouncement;
  static String? _lastLabel;

  /// The most recent label that passed the throttle — test seam.
  @visibleForTesting
  static String? lastAnnounced;

  static void announce(String label) {
    final now = DateTime.now();
    if (_lastLabel == label && _lastAnnouncement != null) {
      final elapsed = now.difference(_lastAnnouncement!);
      if (elapsed.inMilliseconds < 1500) return;
    }
    _lastLabel = label;
    _lastAnnouncement = now;
    lastAnnounced = label;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return; // headless (backgrounded/tests) — no view to announce into
    SemanticsService.sendAnnouncement(views.first, label, TextDirection.ltr);
  }

  static void reset() {
    _lastLabel = null;
    _lastAnnouncement = null;
    lastAnnounced = null;
  }
}
