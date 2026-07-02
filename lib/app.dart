import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';

class HapticWayApp extends StatelessWidget {
  const HapticWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HapticWay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.dark,
          surface: const Color(0xFF1A1A2E),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
      home: const _StartupRouter(),
    );
  }
}

class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  bool? _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _onboardingComplete = prefs.getBool(kPrefKeyOnboardingComplete) ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingComplete == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
        ),
      );
    }
    return _onboardingComplete! ? const HomeScreen() : const OnboardingScreen();
  }
}
