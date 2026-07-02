import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../haptics/intensity_curve.dart';
import '../haptics/tacton.dart';
import '../ui/widgets/status_announcer.dart';
import 'woz_session_log.dart';

/// Hidden Wizard-of-Oz researcher panel (§6.4).
///
/// Opened by a 3-finger long press on the home screen. The researcher injects
/// simulated detections (label + distance) which fire the real haptic + TTS
/// pipeline, and marks observed participant actions. Everything is logged to
/// a JSONL session file. The participant is blindfolded and never sees this.
class WozScreen extends StatefulWidget {
  const WozScreen({super.key});

  @override
  State<WozScreen> createState() => _WozScreenState();
}

class _WozScreenState extends State<WozScreen> {
  // The 7 trained navigation classes (ml/hapticway_labels.txt order).
  static const List<String> _labels = [
    'person', 'bicycle', 'bench', 'chair', 'door', 'staircase', 'pole',
  ];

  static const List<double> _distances = [0.5, 1.0, 1.5, 2.0, 3.0];

  static const List<String> _actions = [
    'stopped', 'turned', 'hesitated', 'near_miss', 'no_reaction',
  ];

  final _log = WozSessionLog();
  double _hapticK = kHapticConstantK;
  double _distance = 1.0;
  String _lastEvent = '—';
  Timer? _clock;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadK();
  }

  Future<void> _loadK() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _hapticK = prefs.getDouble(kPrefKeyHapticK) ?? kHapticConstantK);
  }

  Future<void> _toggleSession() async {
    if (_log.isOpen) {
      _clock?.cancel();
      final path = _log.filePath;
      await _log.close();
      if (!mounted) return;
      setState(() => _lastEvent = 'Session saved: $path');
    } else {
      await _log.open(k: _hapticK);
      _elapsed = Duration.zero;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _elapsed = DateTime.now().difference(_log.sessionStart!));
        }
      });
      if (!mounted) return;
      setState(() => _lastEvent = 'Session started');
    }
  }

  void _inject(String label) {
    final amplitude = IntensityCurve.amplitudeFor(_distance, k: _hapticK);
    Tacton.obstacleAhead(amplitude);
    StatusAnnouncer.announce('$label ahead');
    _log.logSim(label: label, distanceMeters: _distance, amplitude: amplitude);
    setState(() =>
        _lastEvent = 'SIM  $label @ ${_distance.toStringAsFixed(1)} m  '
            '(A=${amplitude.toStringAsFixed(2)})');
  }

  void _markAction(String action) {
    _log.logAction(action);
    setState(() => _lastEvent = 'ACTION  $action');
  }

  @override
  void dispose() {
    _clock?.cancel();
    // Close any session left open so the file isn't truncated mid-write.
    // close() is claim-then-close, so racing _toggleSession is safe.
    unawaited(_log.close());
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final active = _log.isOpen;
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(context, active),
            const SizedBox(height: 12),
            _buildEventTicker(),
            const SizedBox(height: 20),
            _heading('DISTANCE'),
            const SizedBox(height: 8),
            _buildDistanceChips(),
            const SizedBox(height: 20),
            _heading('INJECT DETECTION  (fires haptic + TTS)'),
            const SizedBox(height: 8),
            _buildLabelGrid(active),
            const SizedBox(height: 20),
            _heading('PARTICIPANT ACTION'),
            const SizedBox(height: 8),
            _buildActionRow(active),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool active) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Back to home screen',
        ),
        const Expanded(
          child: Text(
            'WoZ Research Panel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              _formatElapsed(_elapsed),
              style: const TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ElevatedButton(
          onPressed: _toggleSession,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                active ? const Color(0xFFD32F2F) : const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
          ),
          child: Text(active ? 'END' : 'START'),
        ),
      ],
    );
  }

  Widget _buildEventTicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _lastEvent,
        style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 13),
      ),
    );
  }

  Widget _heading(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFB0BEC5),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildDistanceChips() {
    return Wrap(
      spacing: 8,
      children: _distances.map((d) {
        final selected = (_distance - d).abs() < 0.01;
        return ChoiceChip(
          label: Text('${d.toStringAsFixed(1)} m'),
          selected: selected,
          onSelected: (_) => setState(() => _distance = d),
          selectedColor: const Color(0xFF4CAF50),
          backgroundColor: const Color(0xFF0D1B2A),
          labelStyle: TextStyle(
            color: selected ? const Color(0xFF1A1A2E) : const Color(0xFFE0E0E0),
            fontWeight: FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLabelGrid(bool active) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.6,
      children: _labels.map((label) {
        return ElevatedButton(
          // Injection allowed without an open session (for pre-walk rehearsal),
          // but only logged when a session is active.
          onPressed: () => _inject(label),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                active ? const Color(0xFF1B3A5C) : const Color(0xFF0D1B2A),
            foregroundColor: const Color(0xFFE0E0E0),
            side: const BorderSide(color: Color(0xFF444466)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionRow(bool active) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _actions.map((action) {
        return OutlinedButton(
          onPressed: active ? () => _markAction(action) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFFB74D),
            disabledForegroundColor: const Color(0xFF555566),
            side: BorderSide(
              color: active ? const Color(0xFFFFB74D) : const Color(0xFF333344),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(action.replaceAll('_', ' ')),
        );
      }).toList(),
    );
  }
}
