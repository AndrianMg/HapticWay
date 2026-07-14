import 'package:hapticway/research/woz_session_log.dart';

/// In-memory test double for [WozSessionLog] — records every log call and
/// never touches disk. Install with `WozSessionLog.instance = FakeWozSessionLog()`
/// in setUp (and `WozSessionLog.reset()` in tearDown). Mirrors the real
/// contract: log calls are silent no-ops while no session is open.
class FakeWozSessionLog extends WozSessionLog {
  bool _open = false;
  String? _fakePath;
  DateTime? _start;

  /// Every recorded event, oldest first (timestamps omitted for easy matching).
  final List<Map<String, Object?>> events = [];

  /// Puts the fake straight into the "session running" state without disk I/O.
  void seedOpen({String path = 'fake/hapticway_woz_P3_stamp.jsonl'}) {
    _open = true;
    _fakePath = path;
    _start = DateTime.now();
  }

  @override
  bool get isOpen => _open;

  @override
  String? get filePath => _fakePath;

  @override
  DateTime? get sessionStart => _start;

  @override
  Future<void> open({
    required double k,
    required String participantId,
    String condition = 'woz',
  }) async {
    if (_open) return;
    _open = true;
    _start = DateTime.now();
    _fakePath = 'fake/hapticway_woz_${participantId}_stamp.jsonl';
    events.add({
      'event': 'session_start',
      'k': k,
      'participant': participantId,
      'condition': condition,
    });
  }

  @override
  void logSim({
    required String label,
    required double distanceMeters,
    required double amplitude,
    required String direction,
  }) {
    if (!_open) return;
    events.add({
      'event': 'sim',
      'label': label,
      'distance_m': distanceMeters,
      'amplitude': amplitude,
      'direction': direction,
    });
  }

  @override
  void logAction(String action) {
    if (!_open) return;
    events.add({'event': 'action', 'action': action});
  }

  @override
  void logOverride({required bool enabled}) {
    if (!_open) return;
    events.add({'event': 'override', 'enabled': enabled});
  }

  @override
  void logManualPulse({required double amplitude, required int durationMs}) {
    if (!_open) return;
    events.add({
      'event': 'manual_pulse',
      'amplitude': amplitude,
      'duration_ms': durationMs,
    });
  }

  @override
  void logPhase(String mode) {
    if (!_open) return;
    events.add({'event': 'phase', 'mode': mode});
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    events.add({'event': 'session_end'});
  }
}
