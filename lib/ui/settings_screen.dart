import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../haptics/haptic_engine.dart';
import '../research/woz_session_log.dart';
import 'widgets/status_announcer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _k = kHapticConstantK;
  // Stored inverted as kPrefKeyOverride (true = alerts off) — the pref key
  // keeps the historic override polarity; only the UI reads the other way.
  bool _alertsEnabled = true;
  int? _selectedPreset;

  // §7.3 benchmark condition grid: {bright,dim} × {empty,crowded}
  String _benchLighting = 'bright';
  String _benchScene = 'empty';

  static const List<_Preset> _presets = [
    _Preset(label: 'Subtle', k: 0.2),
    _Preset(label: 'Standard', k: 0.5),
    _Preset(label: 'Strong', k: 2.0),
  ];

  static const List<_WoZPulse> _pulses = [
    _WoZPulse(label: 'Subtle', amplitude: 0.2),
    _WoZPulse(label: 'Medium', amplitude: 0.5),
    _WoZPulse(label: 'Strong', amplitude: 0.8),
    _WoZPulse(label: 'Max', amplitude: 1.0),
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final k = prefs.getDouble(kPrefKeyHapticK) ?? kHapticConstantK;
    setState(() {
      _k = k;
      _alertsEnabled = !(prefs.getBool(kPrefKeyOverride) ?? false);
      _selectedPreset = _presetIndexFor(k);
    });
  }

  int? _presetIndexFor(double k) {
    for (int i = 0; i < _presets.length; i++) {
      if ((_presets[i].k - k).abs() < 0.01) return i;
    }
    return null;
  }

  Future<void> _saveK(double k) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kPrefKeyHapticK, k);
    } catch (e) {
      debugPrint('settings: prefs write failed: $e');
    }
  }

  Future<void> _saveAlertsEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPrefKeyOverride, !enabled);
    } catch (e) {
      debugPrint('settings: prefs write failed: $e');
    }
    StatusAnnouncer.announce(
      enabled ? 'Vibration alerts on' : 'Vibration alerts off',
    );
  }

  void _selectPreset(int index) {
    final k = _presets[index].k;
    setState(() {
      _selectedPreset = index;
      _k = k;
    });
    _saveK(k);
  }

  static const _pulseDuration = Duration(milliseconds: 200);

  void _firePulse(_WoZPulse pulse) {
    HapticEngine.vibrate(pulse.amplitude, _pulseDuration);
    // §7.2: leaves a trace in an active WoZ session; no-op otherwise. The
    // duration is passed through so log and pulse can't drift apart.
    WozSessionLog.instance.logManualPulse(
      amplitude: pulse.amplitude,
      durationMs: _pulseDuration.inMilliseconds,
    );
  }

  void _onSliderChanged(double value) {
    final rounded = double.parse(value.toStringAsFixed(1));
    setState(() {
      _k = rounded;
      _selectedPreset = _presetIndexFor(rounded);
    });
    _saveK(rounded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _sectionHeading('HAPTIC SENSITIVITY'),
              const SizedBox(height: 12),
              _buildPresets(),
              const SizedBox(height: 16),
              _buildSliderSection(),
              const SizedBox(height: 28),
              _sectionHeading('HAPTIC ALERTS'),
              const SizedBox(height: 12),
              _buildAlertsToggle(),
              const SizedBox(height: 8),
              _buildTestButton(),
              const SizedBox(height: 28),
              _sectionHeading('MANUAL TRIGGER (Research mode)'),
              const SizedBox(height: 12),
              _buildWoZButtons(),
              const SizedBox(height: 28),
              _sectionHeading('LATENCY BENCHMARK'),
              const SizedBox(height: 12),
              _buildConditionPickers(),
              const SizedBox(height: 12),
              _buildBenchmarkButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        FocusTraversalOrder(
          order: const NumericFocusOrder(1),
          child: Semantics(
            label: 'Back, navigate to home screen',
            button: true,
            excludeSemantics: true,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
        ),
        const Expanded(
          child: Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeading(String title) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFB0BEC5),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildPresets() {
    return Row(
      children: List.generate(_presets.length, (i) {
        final preset = _presets[i];
        final selected = _selectedPreset == i;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _presets.length - 1 ? 8 : 0),
            child: FocusTraversalOrder(
              order: NumericFocusOrder((3 + i).toDouble()),
              child: Semantics(
                label: '${preset.label} preset, k equals ${preset.k}. ${selected ? 'Selected.' : 'Not selected.'} Double tap to select.',
                selected: selected,
                button: true,
                excludeSemantics: true,
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => _selectPreset(i),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected
                          ? const Color(0xFF4CAF50)
                          : Colors.transparent,
                      foregroundColor: selected
                          ? const Color(0xFF1A1A2E)
                          : const Color(0xFFE0E0E0),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF444466),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      preset.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSliderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Custom sensitivity, k equals ${_k.toStringAsFixed(1)}. Adjust with the slider below.',
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Custom  (k = ${_k.toStringAsFixed(2)})',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
        FocusTraversalOrder(
          order: const NumericFocusOrder(6),
          child: Semantics(
            label: 'Sensitivity slider',
            value: 'k equals ${_k.toStringAsFixed(1)}',
            increasedValue: 'k equals ${(_k + 0.1).clamp(0.1, 2.0).toStringAsFixed(1)}',
            decreasedValue: 'k equals ${(_k - 0.1).clamp(0.1, 2.0).toStringAsFixed(1)}',
            hint: 'Minimum 0.1, maximum 2.0. Swipe right to increase, left to decrease.',
            onIncrease: () => _onSliderChanged((_k + 0.1).clamp(0.1, 2.0)),
            onDecrease: () => _onSliderChanged((_k - 0.1).clamp(0.1, 2.0)),
            excludeSemantics: true,
            child: Slider(
              value: _k,
              min: 0.1,
              max: 2.0,
              divisions: 19,
              activeColor: const Color(0xFF4CAF50),
              inactiveColor: const Color(0xFF2A2A3E),
              onChanged: _onSliderChanged,
              semanticFormatterCallback: (v) => 'k equals ${v.toStringAsFixed(1)}',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertsToggle() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(7),
      child: Semantics(
        label: 'Vibration alerts, currently ${_alertsEnabled ? 'on' : 'off'}. Double tap to toggle.',
        toggled: _alertsEnabled,
        excludeSemantics: true,
        child: SwitchListTile(
          title: const Text(
            'Vibration alerts',
            style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 15),
          ),
          value: _alertsEnabled,
          onChanged: (v) {
            setState(() => _alertsEnabled = v);
            _saveAlertsEnabled(v);
          },
          activeThumbColor: const Color(0xFF4CAF50),
          tileColor: const Color(0xFF0D1B2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildTestButton() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(8),
      child: Semantics(
        label: 'Test vibration. Fires haptic pulse at current sensitivity for 300 milliseconds.',
        button: true,
        excludeSemantics: true,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () => HapticEngine.vibrate(
              _k.clamp(0.0, 1.0),
              const Duration(milliseconds: 300),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D1B2A),
              foregroundColor: const Color(0xFFE0E0E0),
              side: const BorderSide(color: Color(0xFF444466)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'TEST VIBRATION',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWoZButtons() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.8,
      children: List.generate(_pulses.length, (i) {
        final pulse = _pulses[i];
        return FocusTraversalOrder(
          order: NumericFocusOrder((9 + i).toDouble()),
          child: Semantics(
            label: '${pulse.label} pulse, amplitude ${pulse.amplitude}, 200 milliseconds.',
            button: true,
            excludeSemantics: true,
            child: OutlinedButton(
              onPressed: () => _firePulse(pulse),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE0E0E0),
                side: const BorderSide(color: Color(0xFF444466)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${pulse.amplitude}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    pulse.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFB0BEC5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // §7.3: condition selectors so each 20-frame run is tagged for the
  // {bright,dim} × {empty,crowded} report grid.
  Widget _buildConditionPickers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _conditionRow(
          title: 'Lighting',
          options: const ['bright', 'dim'],
          selected: _benchLighting,
          onSelect: (v) => setState(() => _benchLighting = v),
          focusOrder: 13,
        ),
        const SizedBox(height: 8),
        _conditionRow(
          title: 'Scene',
          options: const ['empty', 'crowded'],
          selected: _benchScene,
          onSelect: (v) => setState(() => _benchScene = v),
          focusOrder: 14,
        ),
      ],
    );
  }

  Widget _conditionRow({
    required String title,
    required List<String> options,
    required String selected,
    required void Function(String) onSelect,
    required int focusOrder,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            title,
            style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
          ),
        ),
        ...options.asMap().entries.map((entry) {
          final option = entry.value;
          final isSelected = option == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FocusTraversalOrder(
              order: NumericFocusOrder((focusOrder + entry.key * 0.1)),
              child: Semantics(
                label: '$title condition $option. '
                    '${isSelected ? 'Selected.' : 'Not selected.'} Double tap to select.',
                selected: isSelected,
                button: true,
                excludeSemantics: true,
                child: ChoiceChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (_) => onSelect(option),
                  selectedColor: const Color(0xFF4CAF50),
                  backgroundColor: const Color(0xFF0D1B2A),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF1A1A2E)
                        : const Color(0xFFE0E0E0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBenchmarkButton() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(15),
      child: Semantics(
        label: 'Start latency benchmark for $_benchLighting $_benchScene condition. '
            'Collects 20 frames then saves a CSV report.',
        button: true,
        excludeSemantics: true,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _startBenchmark,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D1B2A),
              foregroundColor: const Color(0xFFE0E0E0),
              side: const BorderSide(color: Color(0xFF4CAF50)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'START BENCHMARK  ($_benchLighting / $_benchScene)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  void _startBenchmark() {
    if (mounted) {
      Navigator.pop<String>(context, '${_benchLighting}_$_benchScene');
    }
  }
}

class _Preset {
  final String label;
  final double k;
  const _Preset({required this.label, required this.k});
}

class _WoZPulse {
  final String label;
  final double amplitude;
  const _WoZPulse({required this.label, required this.amplitude});
}
