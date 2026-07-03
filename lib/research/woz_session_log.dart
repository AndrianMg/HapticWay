import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// JSONL logger for Wizard-of-Oz blindfold testing sessions (§6.4).
///
/// Entries contain only simulated-event parameters and researcher-marked
/// participant actions — never frames, never PII. One file per session in the
/// app documents directory: `hapticway_woz_<timestamp>.jsonl`.
class WozSessionLog {
  IOSink? _sink;
  DateTime? _sessionStart;
  String? _filePath;

  bool get isOpen => _sink != null;
  String? get filePath => _filePath;
  DateTime? get sessionStart => _sessionStart;

  Future<void> open({required double k}) async {
    if (_sink != null) return;
    _sessionStart = DateTime.now();
    final dir = await getApplicationDocumentsDirectory();
    final stamp = _sessionStart!
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final file = File('${dir.path}/hapticway_woz_$stamp.jsonl');
    _filePath = file.path;
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    _log({
      'event': 'session_start',
      'ts': _sessionStart!.millisecondsSinceEpoch,
      'k': k,
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

  Future<void> close() async {
    // Claim the sink before any await so a concurrent close (dispose vs END
    // button) can't double-flush or write session_end twice.
    final sink = _sink;
    if (sink == null) return;
    _sink = null;
    final now = DateTime.now();
    sink.writeln(jsonEncode({
      'event': 'session_end',
      'ts': now.millisecondsSinceEpoch,
      'duration_s': now.difference(_sessionStart!).inSeconds,
    }));
    await sink.flush();
    await sink.close();
  }

  void _log(Map<String, dynamic> entry) {
    _sink?.writeln(jsonEncode(entry));
  }
}
