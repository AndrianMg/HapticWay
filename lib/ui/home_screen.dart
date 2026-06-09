import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../benchmark/benchmark_runner.dart';
import '../benchmark/timing_data.dart';
import '../core/constants.dart';
import '../depth/ar_depth_channel.dart';
import '../haptics/haptic_engine.dart';
import '../inference/camera_isolate.dart';
import '../inference/detection.dart';
import 'settings_screen.dart';
import 'widgets/status_announcer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── Prefs ──────────────────────────────────────────────────────────────────
  bool _hapticOverride = false;
  double _hapticK = kHapticConstantK;

  // ── §6.1 ARCore ────────────────────────────────────────────────────────────
  // textureId returned by ArDepthChannel.start(); drives the Texture widget.
  int? _textureId;
  CameraIsolate? _isolate;
  StreamSubscription<List<Detection>>? _detSub;

  // ── UI state ───────────────────────────────────────────────────────────────
  String _statusText = 'Initialising…';
  double _hapticLevel = 0.0;

  // ── Stability filter ───────────────────────────────────────────────────────
  String? _stableLabel;
  int _stableCount = 0;

  // ── Benchmark ──────────────────────────────────────────────────────────────
  final _benchmark = BenchmarkRunner();
  StreamSubscription<TimingData>? _timingSub;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _initAr();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hapticOverride = prefs.getBool(kPrefKeyOverride) ?? false;
      _hapticK = prefs.getDouble(kPrefKeyHapticK) ?? kHapticConstantK;
    });
  }

  // ── §6.1: start ARCore; it owns the camera exclusively ────────────────────
  Future<void> _initAr() async {
    try {
      final texId = await ArDepthChannel.instance.start();
      if (!mounted) return;
      setState(() => _textureId = texId);

      _isolate = CameraIsolate();
      await _isolate!.start();

      _detSub   = _isolate!.detections.listen(_onDetections);
      _timingSub = _isolate!.timing.listen(_onTiming);

      _setStatus('Scanning…');
    } on Exception catch (e) {
      _setStatus('Camera unavailable: $e');
    }
  }

  // ── Detection handler ─────────────────────────────────────────────────────
  void _onDetections(List<Detection> detections) {
    if (!mounted) return;

    if (detections.isEmpty) {
      _stableLabel = null;
      _stableCount = 0;
      setState(() {
        _statusText  = 'Scanning…';
        _hapticLevel = 0.0;
      });
      return;
    }

    final closest = detections.first;

    if (closest.label == _stableLabel) {
      _stableCount++;
    } else {
      _stableLabel = closest.label;
      _stableCount = 1;
    }
    if (_stableCount < kDetectionStabilityFrames) return;

    // §6.1: query real depth at the detection bbox centre.
    // sampleDepth is async but we fire-and-forget the UI update so the haptic
    // does not block; the depth value is incorporated on the next frame if
    // ARCore hasn't responded yet.
    _applyDetection(closest);
  }

  Future<void> _applyDetection(Detection d) async {
    // Query ARCore depth at the normalised centre of the bounding box.
    final nx = d.bbox.center.dx;
    final ny = d.bbox.center.dy;
    final depthM = await ArDepthChannel.instance.sampleDepth(nx, ny);

    double amplitude;
    if (depthM > 0) {
      // §6.1: map real distance [kMax → kMin] to amplitude [0 → 1].
      // An object at kMinDistanceMeters (0.3 m) = full amplitude 1.0.
      // An object at kMaxDistanceMeters (4.0 m) = amplitude 0.0.
      amplitude = ((kMaxDistanceMeters - depthM) /
              (kMaxDistanceMeters - kMinDistanceMeters))
          .clamp(0.0, 1.0);
    } else {
      // ARCore depth unavailable — fall back to bbox-area proxy.
      amplitude = math.sqrt(d.proximityAmplitude).clamp(0.0, 1.0);
    }

    if (!mounted) return;
    setState(() {
      _statusText  = '${d.label} detected (${(d.confidence * 100).round()}%)'
          '${depthM > 0 ? ' — ${depthM.toStringAsFixed(1)} m' : ''}';
      _hapticLevel = amplitude;
    });

    StatusAnnouncer.announce('${d.label} ahead');

    if (!_hapticOverride) {
      HapticEngine.vibrate(
        amplitude * _hapticK.clamp(0.0, 1.0),
        const Duration(milliseconds: 200),
      );
    }
  }

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _statusText = text);
  }

  Future<void> _toggleOverride() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _hapticOverride = !_hapticOverride);
    await prefs.setBool(kPrefKeyOverride, _hapticOverride);
    StatusAnnouncer.announce(
      _hapticOverride ? 'Haptic alerts disabled' : 'Haptic alerts enabled',
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => const SettingsScreen()),
    ).then((benchmarkRequested) {
      _loadPrefs();
      if (benchmarkRequested == true) {
        _benchmark.start(onComplete: _onBenchmarkComplete);
      }
    });
  }

  void _onTiming(TimingData data) {
    _benchmark.addSample(data);
    if (_benchmark.isActive && mounted) {
      setState(() =>
          _statusText = 'Benchmarking… ${_benchmark.collected}/${BenchmarkRunner.kSamples}');
    }
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
    _timingSub?.cancel();
    _detSub?.cancel();
    _isolate?.stop();
    ArDepthChannel.instance.stop();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: FocusTraversalGroup(
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
          ? Texture(textureId: texId)
          : Container(
              color: const Color(0xFF0A0A1A),
              child: Center(
                child: _statusText.contains('unavailable')
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
      child: Semantics(
        liveRegion: true,
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
                  'Haptic override, currently ${_hapticOverride ? 'on' : 'off'}. Double tap to toggle.',
              toggled: _hapticOverride,
              excludeSemantics: true,
              child: SwitchListTile(
                title: const Text(
                  'HAPTIC OVERRIDE',
                  style: TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: _hapticOverride,
                onChanged: (_) => _toggleOverride(),
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
              label: 'Open settings',
              button: true,
              excludeSemantics: true,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _openSettings(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'OPEN SETTINGS',
                    style: TextStyle(fontWeight: FontWeight.bold),
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
