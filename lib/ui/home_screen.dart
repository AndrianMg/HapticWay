import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../benchmark/benchmark_runner.dart';
import '../benchmark/timing_data.dart';
import '../core/constants.dart';
import '../depth/ar_depth_channel.dart';
import '../haptics/intensity_curve.dart';
import '../haptics/tacton.dart';
import '../inference/camera_isolate.dart';
import '../inference/detection.dart';
import '../research/woz_screen.dart';
import '../research/woz_session_log.dart';
import 'settings_screen.dart';
import 'widgets/status_announcer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.detectionSource});

  // Injectable seam for tests — defaults to a real [CameraIsolate] when null.
  final DetectionSource? detectionSource;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ── Prefs ──────────────────────────────────────────────────────────────────
  // Stored inverted as kPrefKeyOverride (true = alerts off) — the pref key and
  // the WoZ session-log schema keep the historic override polarity.
  bool _alertsEnabled = true;
  double _hapticK = kHapticConstantK;

  // ── App lifecycle ──────────────────────────────────────────────────────────
  // The whole pipeline (ARCore session, inference isolate, depth-poll timer)
  // must stop on pause — otherwise the phone keeps vibrating in the user's
  // pocket and the camera stays live while backgrounded.
  bool _pipelineRunning = false;
  bool _resumeAfterPause = false;
  // User-facing PAUSE button — distinct from the lifecycle pause above: while
  // set, nothing (Settings return, WoZ return) may restart the pipeline.
  bool _userPaused = false;
  bool _wozOpen = false;
  bool _settingsOpen = false;
  int _depthFailures = 0;
  Future<void>? _pendingStop;

  // ── §6.1 ARCore ────────────────────────────────────────────────────────────
  // textureId returned by ArDepthChannel.start(); drives the Texture widget.
  int? _textureId;
  DetectionSource? _isolate;
  StreamSubscription<List<Detection>>? _detSub;

  // ── UI state ───────────────────────────────────────────────────────────────
  String _statusText = 'Initialising…';
  double _hapticLevel = 0.0;

  // Debug-only detection overlay (box-alignment check for the letterbox fix).
  List<Detection> _overlayDets = const [];

  // ── Stability filter ───────────────────────────────────────────────────────
  String? _stableLabel;
  int _stableCount = 0;
  ObstacleDirection? _lastDirection;
  // Whole-metre bucket last spoken for the tracked object — hysteresis state
  // for spokenDistanceBucket, reset whenever the tracked label changes.
  int? _spokenDistanceBucket;
  int _emptyFrames = 0;

  // ── Detection display smoothing ────────────────────────────────────────────
  // Prevents concurrent depth queries and smooths jittery confidence/distance.
  bool _applyBusy = false;
  double _smoothConf  = 0.0;
  double _smoothDepth = 0.0;

  // ── §6.2 depth-poll haptic radar ───────────────────────────────────────────
  // Samples the centre of the frame so the haptic fires even when YOLO
  // detects nothing (e.g. walking toward a plain wall). Adaptive cadence:
  // kDepthPollNearInterval while a surface is in haptic range, backing off to
  // kDepthPollFarInterval when nothing is close (battery).
  Timer? _depthPollTimer;
  bool _depthPollBusy = false;

  // ── §6.4 hidden WoZ panel ──────────────────────────────────────────────────
  // 3-finger long press (800 ms) anywhere on the screen opens the researcher
  // panel. Tracked via raw pointer events — GestureDetector has no multi-touch
  // long-press recognizer.
  final Set<int> _activePointers = {};
  Timer? _wozTrigger;

  // ── Benchmark ──────────────────────────────────────────────────────────────
  final _benchmark = BenchmarkRunner();
  StreamSubscription<TimingData>? _timingSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _startPipeline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `paused` only — `inactive` also fires for permission dialogs and the
    // notification shade, which would thrash the ARCore session.
    if (state == AppLifecycleState.paused && _pipelineRunning) {
      _resumeAfterPause = true;
      _setStatus('Paused');
      _pendingStop = _stopPipeline();
      unawaited(_pendingStop);
    } else if (state == AppLifecycleState.resumed && _resumeAfterPause) {
      _resumeAfterPause = false;
      unawaited(_resumePipeline());
    }
  }

  Future<void> _resumePipeline() async {
    // A fast pause→resume must not start a new pipeline while the old one is
    // still tearing down — stop() would null out the fresh isolate reference.
    await _pendingStop;
    _pendingStop = null;
    await _startPipeline();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _alertsEnabled = !(prefs.getBool(kPrefKeyOverride) ?? false);
      _hapticK = prefs.getDouble(kPrefKeyHapticK) ?? kHapticConstantK;
    });
  }

  // ── §6.1: start ARCore; it owns the camera exclusively ────────────────────
  Future<void> _startPipeline() async {
    if (_pipelineRunning) return;
    try {
      final texId = await ArDepthChannel.instance.start();
      if (!mounted) return;
      setState(() => _textureId = texId);

      // Fresh instance per start — a stopped CameraIsolate cannot restart
      // (its broadcast controllers are closed).
      _isolate = widget.detectionSource ?? CameraIsolate();
      await _isolate!.start();

      _detSub = _isolate!.detections.listen(
        _onDetections,
        onError: (Object e) => _setStatus('Detection unavailable: $e'),
      );
      _timingSub = _isolate!.timing.listen(_onTiming);

      _setStatus('Scanning…');
      // Running must be set before the poll starts — _startDepthPoll refuses
      // to run against a stopped pipeline.
      _pipelineRunning = true;
      _startDepthPoll();
    } on PlatformException catch (e) {
      _setStatus('Camera unavailable: ${e.message ?? e.code}');
    } catch (e) {
      // Errors too (TypeError, FlutterError from a missing asset) — an
      // `on Exception` clause would miss them and leave the spinner forever.
      _setStatus('Camera unavailable: $e');
    }
  }

  void _startDepthPoll() {
    // !_pipelineRunning covers the user-paused case: returning from Settings
    // or WoZ must not start polling against a dead AR session.
    if (_wozOpen || _settingsOpen || !_pipelineRunning) return;
    _depthPollTimer?.cancel();
    // Always begin at the near cadence — responsiveness right after
    // start/resume matters more than one cheap tick.
    _scheduleDepthPoll(kDepthPollNearInterval);
  }

  // Adaptive cadence: the next tick is scheduled only after the current
  // sample resolves — near interval while a surface sits inside haptic range,
  // far interval when everything is out of range (or depth is unavailable).
  void _scheduleDepthPoll(Duration interval) {
    late final Timer timer;
    timer = Timer(interval, () async {
      final depthM = await _pollDepth();
      // Every stop path (pipeline stop, WoZ/Settings push, restart) cancels
      // and replaces _depthPollTimer — if it no longer points at this timer,
      // the chain was stopped while sampleDepth was in flight: don't
      // resurrect it.
      if (!mounted || !identical(_depthPollTimer, timer)) return;
      final near = depthM != null && depthM > 0 && depthM < kMaxDistanceMeters;
      _scheduleDepthPoll(
          near ? kDepthPollNearInterval : kDepthPollFarInterval);
    });
    _depthPollTimer = timer;
  }

  Future<void> _stopPipeline() async {
    _pipelineRunning = false;
    _depthPollTimer?.cancel();
    _depthPollTimer = null;
    // Broadcast-subscription cancel detaches the listener synchronously and
    // its returned future is the root-zone _nullFuture, which never resumes
    // inside a fake-async test zone — never await it here.
    unawaited(_timingSub?.cancel());
    _timingSub = null;
    unawaited(_detSub?.cancel());
    _detSub = null;
    final isolate = _isolate;
    _isolate = null;
    // AR session (camera) down first — that is the safety-critical part —
    // then the inference isolate.
    await ArDepthChannel.instance.stop();
    await isolate?.stop();
    // The texture id is dead once the native session stops — rendering it
    // would show a frozen/invalid frame on resume until the new id arrives.
    if (mounted) {
      setState(() {
        _textureId = null;
        _hapticLevel = 0.0;
      });
    }
  }

  // ── §6.2 depth-poll haptic radar ──────────────────────────────────────────
  // Runs independently of YOLO detection so the haptic fires for any surface
  // in the centre of the frame (walls, floors, plain obstacles). Returns the
  // sampled depth (null on failure) so the caller can pick the next cadence.
  Future<double?> _pollDepth() async {
    if (!mounted || _depthPollBusy) return null;
    _depthPollBusy = true;
    try {
      final depthM = await ArDepthChannel.instance
          .sampleDepth(0.35, 0.35, 0.65, 0.65);
      if (!mounted) return null;
      if (depthM <= 0) {
        if (_hapticLevel > 0) setState(() => _hapticLevel = 0.0);
        return depthM;
      }
      final amplitude = IntensityCurve.amplitudeFor(depthM, k: _hapticK);
      setState(() => _hapticLevel = amplitude);
      if (_alertsEnabled && depthM < kMaxDistanceMeters) {
        Tacton.obstacleAhead(amplitude);
      }
      _depthFailures = 0;
      return depthM;
    } catch (e) {
      // A lost/paused AR session throws here on every tick — announce once at
      // the threshold transition, never per tick.
      _depthFailures++;
      if (_depthFailures == 5) _setStatus('Depth sensing unavailable');
      return null;
    } finally {
      _depthPollBusy = false;
    }
  }

  // ── Detection handler ─────────────────────────────────────────────────────
  void _onDetections(List<Detection> detections) {
    if (!mounted) return;

    // Debug overlay: show every frame's raw boxes so box alignment is visible.
    if (kDebugMode) setState(() => _overlayDets = detections);

    if (detections.isEmpty) {
      // Loss-side twin of the stability gate below: one empty frame is bbox
      // jitter, not a departed obstacle. Flipping instantly made the status
      // flap detection↔Scanning at frame rate — with the card as a liveRegion
      // that flood went straight to TalkBack (§7.4 pre-audit finding).
      if (_stableLabel == null) return; // already scanning
      if (++_emptyFrames < kDetectionLossFrames) return;
      _stableLabel = null;
      _stableCount = 0;
      _lastDirection = null;
      _spokenDistanceBucket = null;
      _emptyFrames = 0;
      _setStatus('Scanning…');
      return;
    }
    _emptyFrames = 0;

    final closest = detections.first;

    if (closest.label == _stableLabel) {
      _stableCount++;
    } else {
      _stableLabel  = closest.label;
      _stableCount  = 1;
      _smoothConf   = 0.0;
      _smoothDepth  = 0.0;
      _lastDirection = null;
      _spokenDistanceBucket = null;
    }
    if (_stableCount < kDetectionStabilityFrames) return;

    // Guard: skip if a depth query is already in flight — prevents concurrent
    // setState calls that cause the chaotic percentage/distance jitter.
    if (_applyBusy) return;
    _applyDetection(closest);
  }

  // Updates status text with the detected object's label, bbox depth and
  // direction, and fires the directional tacton when the object sits outside
  // the depth-poll radar's centre window. Centre objects stay with _pollDepth
  // so nothing double-fires.
  Future<void> _applyDetection(Detection d) async {
    _applyBusy = true;
    try {
      final depthM = await ArDepthChannel.instance.sampleDepth(
          d.bbox.left, d.bbox.top, d.bbox.right, d.bbox.bottom);

      // EMA smoothing (α=0.3) — damps per-frame jitter in confidence and depth.
      _smoothConf  = _smoothConf  * 0.7 + d.confidence * 0.3;
      if (depthM > 0) {
        _smoothDepth = (_smoothDepth > 0)
            ? _smoothDepth * 0.7 + depthM * 0.3
            : depthM;
      }

      final direction = directionWithHysteresis(
          (d.bbox.left + d.bbox.right) / 2, _lastDirection);
      _lastDirection = direction;

      // Field finding (§7.4): speech carried no range at all — TalkBack users
      // heard "door ahead" with no idea whether that meant 1 m or 4 m.
      // Bucketed to whole metres with hysteresis so a jittering depth cannot
      // alternate strings past the announcer's identical-string throttle.
      if (_smoothDepth > 0) {
        _spokenDistanceBucket =
            spokenDistanceBucket(_smoothDepth, _spokenDistanceBucket);
      }

      if (!mounted) return;
      setState(() {
        _statusText = '${d.label} detected (${(_smoothConf * 100).round()}%)'
            '${_smoothDepth > 0 ? ' — ${_smoothDepth.toStringAsFixed(1)} m' : ''}'
            '${direction == ObstacleDirection.ahead ? '' : ' — ${direction.name}'}';
      });

      StatusAnnouncer.announce(direction.announcement(d.label,
          distanceMetres: _smoothDepth > 0 ? _spokenDistanceBucket : null));

      if (direction != ObstacleDirection.ahead &&
          _alertsEnabled &&
          !_wozOpen &&
          !_settingsOpen &&
          depthM > 0 &&
          depthM < kMaxDistanceMeters) {
        unawaited(Tacton.obstacle(direction,
            IntensityCurve.directionalAmplitudeFor(depthM, k: _hapticK)));
      }
    } finally {
      _applyBusy = false;
    }
  }

  // Status changes speak through StatusAnnouncer's 1500 ms funnel — the card
  // is deliberately not a liveRegion, so this is the only spoken-status path.
  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _statusText = text);
    StatusAnnouncer.announce(text);
  }

  Future<void> _toggleAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _alertsEnabled = !_alertsEnabled);
    // §7.2: alert toggles must appear in the session record. The log's
    // `enabled` field keeps the historic override polarity (true = alerts
    // off) so session records stay comparable. No-op when no WoZ session is
    // open.
    WozSessionLog.instance.logOverride(enabled: !_alertsEnabled);
    try {
      await prefs.setBool(kPrefKeyOverride, !_alertsEnabled);
    } catch (e) {
      debugPrint('home: prefs write failed: $e');
    }
    StatusAnnouncer.announce(
      _alertsEnabled ? 'Vibration alerts on' : 'Vibration alerts off',
    );
    if (_alertsEnabled) {
      await Tacton.manualOverrideOff();
    } else {
      await Tacton.manualOverrideOn();
    }
  }

  // User-facing pause — the biggest battery lever. Reuses the lifecycle
  // teardown, so camera, inference isolate, and depth poll stop together.
  Future<void> _togglePause() async {
    if (_userPaused) {
      setState(() => _userPaused = false);
      await _startPipeline();
    } else {
      setState(() => _userPaused = true);
      _setStatus('Paused');
      await _stopPipeline();
    }
  }

  // ── §6.4 WoZ panel activation ─────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent e) {
    _activePointers.add(e.pointer);
    if (_activePointers.length == 3) {
      _wozTrigger?.cancel();
      _wozTrigger = Timer(const Duration(milliseconds: 800), _openWoz);
    }
  }

  void _onPointerEnd(int pointer) {
    _activePointers.remove(pointer);
    if (_activePointers.length < 3) _wozTrigger?.cancel();
  }

  Future<void> _openWoz() async {
    _activePointers.clear();
    if (!mounted) return;
    // Pause the real depth radar so simulated events aren't contaminated by
    // real-depth vibrations during a WoZ session. _wozOpen also stops a
    // pause/resume cycle from restarting the timer underneath the session.
    _wozOpen = true;
    _depthPollTimer?.cancel();
    _depthPollTimer = null;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const WozScreen()),
    );
    _wozOpen = false;
    if (!mounted) return;
    _startDepthPoll();
  }

  void _openSettings(BuildContext context) {
    // Same contract as the WoZ panel: live haptics must stay silent under the
    // Settings route — the user is adjusting intensity there, often mid
    // TEST VIBRATION. _settingsOpen also stops a pause/resume cycle from
    // restarting the timer while Settings is still open.
    _settingsOpen = true;
    _depthPollTimer?.cancel();
    _depthPollTimer = null;
    Navigator.push<String>(
      context,
      MaterialPageRoute<String>(builder: (_) => const SettingsScreen()),
    ).then((benchmarkCondition) {
      _settingsOpen = false;
      if (mounted) _startDepthPoll();
      _loadPrefs();
      if (benchmarkCondition != null) {
        _benchmark.start(
          condition: benchmarkCondition,
          onComplete: _onBenchmarkComplete,
          onError: _onBenchmarkError,
        );
      }
    });
  }

  void _onTiming(TimingData data) {
    _benchmark.addSample(data);
    if (_benchmark.isActive && mounted) {
      setState(() => _statusText =
          'Benchmarking ${_benchmark.condition}… ${_benchmark.collected}/${BenchmarkRunner.kSamples}');
    }
  }

  void _onBenchmarkError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Benchmark failed: $error'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _onBenchmarkComplete(String path) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Benchmark saved: $path'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wozTrigger?.cancel();
    // Backstop for a forgotten END: the WoZ session outlives the panel route,
    // so app teardown is the last chance to write session_end.
    unawaited(WozSessionLog.instance.close());
    unawaited(_stopPipeline());
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      // §6.4: raw pointer tracking for the hidden 3-finger long press.
      // Translucent so normal taps still reach the buttons underneath.
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: (e) => _onPointerEnd(e.pointer),
        onPointerCancel: (e) => _onPointerEnd(e.pointer),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(child: _buildViewfinder()),
                _buildStatusCard(),
                _buildIntensityBar(),
                _buildControls(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                'HapticWay',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: Semantics(
              label: 'Open settings',
              button: true,
              // excludeSemantics drops the child's tap action with the rest
              // of its semantics — TalkBack double-tap dispatches the node's
              // tap action, so every excluded control must declare one.
              onTap: () => _openSettings(context),
              excludeSemantics: true,
              child: IconButton(
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.settings, color: Colors.white),
                iconSize: 28,
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Open settings',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    final texId = _textureId;
    return ExcludeSemantics(
      // §6.1: Texture widget backed by ARCore's ImageConsumer.
      // Falls back to a loading spinner until the ARCore session is ready.
      child: texId != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Texture(textureId: texId),
                // Debug-only box overlay for the letterbox-fix alignment check.
                if (kDebugMode)
                  CustomPaint(painter: _DetectionOverlayPainter(_overlayDets)),
              ],
            )
          : Container(
              color: const Color(0xFF0A0A1A),
              child: Center(
                // Paused first: a deliberate pause must read as paused, not
                // as an eternal loading spinner.
                child: _userPaused
                    ? const Icon(Icons.pause_circle_outlined,
                        color: Color(0xFF444466), size: 64)
                    : _statusText.contains('unavailable')
                        ? const Icon(Icons.no_photography_outlined,
                            color: Color(0xFF444466), size: 64)
                        : const CircularProgressIndicator(
                            color: Color(0xFF4CAF50)),
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(3),
      // Deliberately NOT a liveRegion: this text mutates at frame rate (EMA'd
      // confidence/depth), and a live region hands every mutation to TalkBack
      // with no throttle — the speech queue backed up into delayed, repeated
      // announcements. Spoken status goes through StatusAnnouncer instead;
      // focusing the card still reads the full detail on demand.
      child: Semantics(
        label: _statusText,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _hapticLevel > 0
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntensityBar() {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Row(
          children: [
            const Text(
              'HAPTIC',
              style: TextStyle(
                color: Color(0xFFB0BEC5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LinearProgressIndicator(
                value: _hapticLevel,
                backgroundColor: const Color(0xFF2A2A3E),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _hapticLevel > 0.6
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFF4CAF50),
                ),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: Semantics(
              label:
                  'Vibration alerts, currently ${_alertsEnabled ? 'on' : 'off'}. Double tap to toggle.',
              toggled: _alertsEnabled,
              onTap: _toggleAlerts,
              excludeSemantics: true,
              child: SwitchListTile(
                title: const Text(
                  'VIBRATION ALERTS',
                  style: TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: _alertsEnabled,
                onChanged: (_) => _toggleAlerts(),
                activeThumbColor: const Color(0xFF4CAF50),
                tileColor: const Color(0xFF0D1B2A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FocusTraversalOrder(
            order: const NumericFocusOrder(5),
            child: Semantics(
              label: _userPaused
                  ? 'Resume camera and vibration alerts'
                  : 'Pause camera and vibration alerts',
              button: true,
              onTap: _togglePause,
              excludeSemantics: true,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _togglePause,
                  style: ElevatedButton.styleFrom(
                    // Orange while paused — the app is not watching for
                    // obstacles until the user resumes.
                    backgroundColor: _userPaused
                        ? const Color(0xFFFF6B35)
                        : const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _userPaused ? 'RESUME' : 'PAUSE',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Debug-only painter: draws detection boxes (normalised frame coords) over the
/// camera preview so the letterbox-inverse box alignment can be verified by eye.
class _DetectionOverlayPainter extends CustomPainter {
  final List<Detection> dets;
  const _DetectionOverlayPainter(this.dets);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFFF6B35);

    for (final d in dets) {
      final rect = Rect.fromLTRB(
        d.bbox.left * size.width,
        d.bbox.top * size.height,
        d.bbox.right * size.width,
        d.bbox.bottom * size.height,
      );
      canvas.drawRect(rect, stroke);

      final tp = TextPainter(
        text: TextSpan(
          text: ' ${d.label} ${(d.confidence * 100).round()}% ',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            backgroundColor: Color(0xFFFF6B35),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, (rect.top - 14).clamp(0.0, size.height)));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter old) =>
      !identical(old.dets, dets);
}
