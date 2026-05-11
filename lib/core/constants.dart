const int kInferenceLatencyBudgetMs = 50;
const double kMinConfidence = 0.55;
const double kHapticConstantK = 0.5;
const double kMinDistanceMeters = 0.3;
const double kMaxDistanceMeters = 4.0;

const String kPrefKeyHapticK = 'haptic_k';
const String kPrefKeyOverride = 'haptic_override';
const String kPrefKeyOnboardingComplete = 'onboarding_complete';

const Duration kAnnouncementThrottle = Duration(milliseconds: 1500);
const int kMaxConsecutiveFailedFrames = 3;
