import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// JSONL logger for Wizard-of-Oz blindfold testing sessions (§6.4).
///
/// Entries contain only simulated-event parameters and researcher-marked
/// participant actions — never frames, never PII. One file per session in the
/// app documents directory: `hapticway_woz_<participant>_<timestamp>.jsonl`.
///
/// The session lives on [instance] app-wide so the Home and Settings routes
/// can log override toggles and manual pulses while a session spans a live
/// segment (§7.2). It closes only via the panel's END button, plus an
/// app-teardown backstop in HomeScreen.dispose.
class WozSessionLog {
  /// The app-wide session. Mutable so widget tests can install a fake.
  static WozSessionLog instance = WozSessionLog();

  @visibleForTesting
  static void reset() {
    unawaited(instance.close());
    instance = WozSessionLog();
  }

  File? _file;
  DateTime? _sessionStart;
  String? _filePath;

  bool get isOpen => _file != null;
  String? get filePath => _filePath;
  DateTime? get sessionStart => _sessionStart;

  Future<void> open({
    required double k,
    required String participantId,
    String condition = 'woz',
  }) async {
    if (_file != null) return;
    // Whitelist so a typo can't inject path separators into the filename; the
    // same sanitized value goes into the log so file and record always agree.
    var participant =
        participantId.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (participant.length > 20) participant = participant.substring(0, 20);
    if (participant.isEmpty) participant = 'anon';
    _sessionStart = DateTime.now();
    final dir = await getApplicationDocumentsDirectory();
    final stamp = _sessionStart!
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final file = File('${dir.path}/hapticway_woz_${participant}_$stamp.jsonl');
    _filePath = file.path;
    _file = file;
    _log({
      'event': 'session_start',
      'ts': _sessionStart!.millisecondsSinceEpoch,
      'k': k,
      'participant': participant,
      'condition': condition,
    });
  }

  /// A simulated detection injected by the researcher.
  void logSim({
    required String label,
    required double distanceMeters,
    required double amplitude,
    required String direction,
  }) {
    _log({
      'event': 'sim',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'label': label,
      'distance_m': distanceMeters,
      'amplitude': amplitude,
      'direction': direction,
    });
  }

  /// A real participant action, marked manually by the researcher.
  void logAction(String action) {
    _log({
      'event': 'action',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'action': action,
    });
  }

  /// Manual haptic-override toggle (§7.2). `enabled` means haptics are
  /// disabled, matching HomeScreen's `_hapticOverride` semantics.
  void logOverride({required bool enabled}) {
    _log({
      'event': 'override',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'enabled': enabled,
    });
  }

  /// A fixed-amplitude pulse fired from Settings' manual-trigger grid (§4.5).
  void logManualPulse({required double amplitude, required int durationMs}) {
    _log({
      'event': 'manual_pulse',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'amplitude': amplitude,
      'duration_ms': durationMs,
    });
  }

  /// Panel entered ('woz') or left ('live') while the session stays open, so
  /// analysis can split simulated segments from live-pipeline segments.
  void logPhase(String mode) {
    _log({
      'event': 'phase',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'mode': mode,
    });
  }

  Future<void> close() async {
    // Claim the file before writing so a concurrent close (END button vs the
    // HomeScreen teardown backstop) can't write session_end twice.
    final file = _file;
    if (file == null) return;
    _file = null;
    final now = DateTime.now();
    file.writeAsStringSync(
      '${jsonEncode({
            'event': 'session_end',
            'ts': now.millisecondsSinceEpoch,
            'duration_s': now.difference(_sessionStart!).inSeconds,
          })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Newest session file on disk — export fallback after an app restart.
  static Future<String?> latestFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.uri.pathSegments.last.startsWith('hapticway_woz_') &&
            f.path.endsWith('.jsonl'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    return files.last.path;
  }

  // Synchronous append + flush per event: a session spans a 20-minute walk,
  // so every line must survive a process death. Events arrive a few per
  // minute at ~100 bytes each — buffering buys nothing here, and an IOSink
  // throws if written while a flush is in flight.
  void _log(Map<String, dynamic> entry) {
    _file?.writeAsStringSync('${jsonEncode(entry)}\n',
        mode: FileMode.append, flush: true);
  }
}
