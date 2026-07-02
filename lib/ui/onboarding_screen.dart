import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../inference/camera_isolate.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.homeDetectionSource});

  // Test-only seam, threaded through to the HomeScreen this navigates to on
  // grant — defaults to null (a real CameraIsolate) in production.
  final DetectionSource? homeDetectionSource;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _permissionDenied = false;
  bool _permanentlyDenied = false;
  bool _loading = false;

  Future<void> _onAgree() async {
    setState(() => _loading = true);

    final status = await Permission.camera.request();
    if (!mounted) return;

    // Allowlist granted only — restricted/limited/provisional must not fall
    // through to a HomeScreen with a non-functional camera.
    if (!status.isGranted) {
      setState(() {
        _permissionDenied = true;
        _permanentlyDenied = status.isPermanentlyDenied;
        _loading = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setBool(kPrefKeyOnboardingComplete, true);
    } catch (e) {
      debugPrint('onboarding: prefs write failed: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(detectionSource: widget.homeDetectionSource),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitle(),
                const SizedBox(height: 32),
                _buildSafetyNotice(),
                const SizedBox(height: 24),
                _buildHowItWorks(),
                const SizedBox(height: 24),
                _buildConsentSection(),
                const SizedBox(height: 20),
                if (_permissionDenied) ...[
                  _buildPermissionError(),
                  const SizedBox(height: 12),
                ],
                _buildAgreeButton(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: Semantics(
        header: true,
        label: 'HapticWay. Navigation aid for students.',
        excludeSemantics: true,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HapticWay',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Navigation aid for students',
              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyNotice() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: Semantics(
        label: 'Safety notice. HapticWay is a navigation aid. '
            'It does not replace your cane or guide dog. '
            'Always use your primary mobility aid alongside this app.',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0A00),
            border: Border.all(color: const Color(0xFFFF6B35), width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B35), size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAFETY NOTICE',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'HapticWay is a navigation aid. It does NOT replace '
                      'your cane or guide dog. Always use your primary '
                      'mobility aid alongside this app.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHowItWorks() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(3),
      child: Semantics(
        label: 'How it works. '
            'Camera detects obstacles up to 4 metres ahead. '
            'Vibration intensity shows how close they are. '
            'No data ever leaves your device. No internet needed.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HOW IT WORKS',
              style: TextStyle(
                color: Color(0xFFB0BEC5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.camera_alt_outlined,
                    text: 'Camera detects obstacles up to 4 metres ahead.',
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.vibration,
                    text: 'Vibration intensity shows how close they are.',
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.lock_outline,
                    text: 'No data ever leaves your device. No internet needed.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'CONSENT',
            style: TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 10),
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: Semantics(
            label: 'I understand HapticWay will access my camera and vibration '
                'motor. No images are stored or transmitted. '
                'I can withdraw consent at any time in Settings.',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'I understand HapticWay will access my camera and vibration '
                'motor. No images are stored or transmitted. '
                'I can withdraw at any time in Settings.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionError() {
    // Once permanently denied, re-requesting is a dead end (the system never
    // re-prompts) — the only way forward is the app's settings page.
    final message = _permanentlyDenied
        ? 'Camera permission is required for obstacle detection. '
            'The system will no longer ask — enable it in system settings.'
        : 'Camera permission is required for obstacle detection. '
            'Go to Settings → Apps → HapticWay → Permissions to enable it.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: _permanentlyDenied
              ? 'Camera permission required. The system will no longer ask. '
                  'Use the open settings button below to enable camera access.'
              : 'Camera permission required. '
                  'Go to Settings, then Apps, then HapticWay, '
                  'then Permissions to enable camera access.',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A0A0A),
              border: Border.all(color: Colors.redAccent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 13, height: 1.4),
            ),
          ),
        ),
        if (_permanentlyDenied) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Open system settings to enable camera access',
            button: true,
            excludeSemantics: true,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: openAppSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D1B2A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFF4CAF50)),
                  ),
                ),
                child: const Text(
                  'OPEN SETTINGS',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAgreeButton() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(5),
      child: Semantics(
        label: 'I agree, get started. '
            'Activates camera and vibration access and opens the navigation screen.',
        button: true,
        excludeSemantics: true,
        child: SizedBox(
          width: double.infinity,
          height: 72,
          child: ElevatedButton(
            onPressed: _loading ? null : _onAgree,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: const Color(0xFF1A1A2E),
              disabledBackgroundColor: const Color(0xFF2A5A2A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _loading
                ? const CircularProgressIndicator(color: Color(0xFF1A1A2E))
                : const Text(
                    '✓  I AGREE — GET STARTED',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF4CAF50), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
