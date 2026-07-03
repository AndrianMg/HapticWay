const int kInferenceLatencyBudgetMs = 50;
const double kMinConfidence = 0.45;
const double kHapticConstantK = 0.5;
const double kMinDistanceMeters = 0.3;
const double kMaxDistanceMeters = 4.0;

const String kPrefKeyHapticK = 'haptic_k';
const String kPrefKeyOverride = 'haptic_override';
const String kPrefKeyOnboardingComplete = 'onboarding_complete';

const Duration kAnnouncementThrottle = Duration(milliseconds: 1500);
const int kMaxConsecutiveFailedFrames = 3;
const int kDetectionStabilityFrames = 4;

// Direction bands for a detection's bbox centre-x — aligned with the
// 0.35–0.65 centre window the depth-poll radar samples, so "ahead" means
// the same thing in both systems.
const double kDirectionLeftBound = 0.35;
const double kDirectionRightBound = 0.65;

// Once in a direction band, the centre-x must cross the boundary by this
// margin before the direction changes — bbox jitter at a boundary must not
// flip announcements or patterns frame-to-frame.
const double kDirectionHysteresis = 0.03;
