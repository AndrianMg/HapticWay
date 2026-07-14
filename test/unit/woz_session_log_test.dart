import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/research/woz_session_log.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../support/fake_path_provider_platform.dart';

// Plain test() on purpose: real file I/O never completes inside testWidgets'
// fake-async zone.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('woz_log_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    WozSessionLog.reset();
  });

  tearDown(() {
    WozSessionLog.reset();
    tempDir.deleteSync(recursive: true);
  });

  List<Map<String, dynamic>> readEvents(String path) => File(path)
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();

  test('open writes session_start with k, participant, and condition', () async {
    final log = WozSessionLog.instance;
    await log.open(k: 0.5, participantId: 'P3');

    expect(log.isOpen, isTrue);
    expect(log.filePath, contains('hapticway_woz_P3_'));
    final events = readEvents(log.filePath!);
    expect(events, hasLength(1));
    expect(events.single['event'], 'session_start');
    expect(events.single['k'], 0.5);
    expect(events.single['participant'], 'P3');
    expect(events.single['condition'], 'woz');
    expect(events.single['ts'], isA<int>());
  });

  test('a full session round trip produces well-formed JSONL', () async {
    final log = WozSessionLog.instance;
    await log.open(k: 0.8, participantId: 'P1');
    log.logSim(
      label: 'person',
      distanceMeters: 1.5,
      amplitude: 0.36,
      direction: 'left',
    );
    log.logPhase('live');
    log.logOverride(enabled: true);
    log.logManualPulse(amplitude: 1.0, durationMs: 200);
    log.logPhase('woz');
    log.logAction('false_positive');
    await log.close();

    final events = readEvents(log.filePath!);
    expect(events.map((e) => e['event']).toList(), [
      'session_start',
      'sim',
      'phase',
      'override',
      'manual_pulse',
      'phase',
      'action',
      'session_end',
    ]);
    expect(events.every((e) => e['ts'] is int), isTrue);
    expect(events[1]['label'], 'person');
    expect(events[1]['distance_m'], 1.5);
    expect(events[1]['amplitude'], 0.36);
    expect(events[1]['direction'], 'left');
    expect(events[2]['mode'], 'live');
    expect(events[3]['enabled'], isTrue);
    expect(events[4]['amplitude'], 1.0);
    expect(events[4]['duration_ms'], 200);
    expect(events[5]['mode'], 'woz');
    expect(events[6]['action'], 'false_positive');
    expect(events.last['duration_s'], isA<int>());
    expect(events.last['duration_s'] as int, greaterThanOrEqualTo(0));
  });

  test('participant ID is sanitized in both filename and record', () async {
    final log = WozSessionLog.instance;
    await log.open(k: 0.5, participantId: ' P 3/../x ');

    expect(log.filePath, contains('hapticway_woz_P3x_'));
    expect(readEvents(log.filePath!).single['participant'], 'P3x');
  });

  test('a blank participant ID falls back to anon', () async {
    final log = WozSessionLog.instance;
    await log.open(k: 0.5, participantId: '   ');

    expect(log.filePath, contains('hapticway_woz_anon_'));
    expect(readEvents(log.filePath!).single['participant'], 'anon');
  });

  test('double close writes one session_end; logging after close is a no-op',
      () async {
    final log = WozSessionLog.instance;
    await log.open(k: 0.5, participantId: 'P2');
    await log.close();
    await log.close();
    log.logAction('stopped');
    log.logOverride(enabled: true);

    final events = readEvents(log.filePath!);
    expect(events.map((e) => e['event']).toList(),
        ['session_start', 'session_end']);
  });

  test('latestFilePath returns the most recently modified session file',
      () async {
    final log = WozSessionLog.instance;
    await log.open(k: 0.5, participantId: 'P1');
    await log.close();
    final first = log.filePath!;

    await log.open(k: 0.5, participantId: 'P2');
    await log.close();
    final second = log.filePath!;
    expect(second, isNot(first));

    // Force a deterministic mtime ordering — same-second writes are below
    // some filesystems' timestamp resolution.
    File(first).setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 1)));

    // open() joins with '/', listSync() with the platform separator —
    // compare filenames, not full paths.
    final latest = await WozSessionLog.latestFilePath();
    expect(latest, isNotNull);
    expect(latest!.split(RegExp(r'[/\\]')).last,
        second.split(RegExp(r'[/\\]')).last);
  });
}
