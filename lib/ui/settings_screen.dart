import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../haptics/haptic_engine.dart';
import 'widgets/status_announcer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _k = kHapticConstantK;
  bool _hapticOverride = false;
  int? _selectedPreset;

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
    final k = prefs.getDouble(kPrefKeyHapticK) ?? kHapticConstantK;
    setState(() {
      _k = k;
      _hapticOverride = prefs.getBool(kPrefKeyOverride) ?? false;
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kPrefKeyHapticK, k);
  }

  Future<void> _saveOverride(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefKeyOverride, value);
    StatusAnnouncer.announce(
      value ? 'Haptic alerts disabled' : 'Haptic alerts enabled',
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
              _buildOverrideToggle(),
              const SizedBox(height: 8),
              _buildTestButton(),
              const SizedBox(height: 28),
              _sectionHeading('MANUAL TRIGGER (Research mode)'),
              const SizedBox(height: 12),
              _buildWoZButtons(),
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

  Widget _buildOverrideToggle() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(7),
      child: Semantics(
        label: 'Haptic override, currently ${_hapticOverride ? 'on' : 'off'}. Double tap to toggle.',
        toggled: _hapticOverride,
        excludeSemantics: true,
        child: SwitchListTile(
          title: const Text(
            'Haptic override',
            style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 15),
          ),
          value: _hapticOverride,
          onChanged: (v) {
            setState(() => _hapticOverride = v);
            _saveOverride(v);
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
              onPressed: () => HapticEngine.vibrate(
                pulse.amplitude,
                const Duration(milliseconds: 200),
              ),
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
