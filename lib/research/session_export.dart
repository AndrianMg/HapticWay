import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

export 'package:share_plus/share_plus.dart' show ShareResult, ShareResultStatus;

/// Thin wrapper over the OS share sheet so a WoZ session log can be pulled
/// off-device without adb (DPIA: logs are pulled and wiped after each
/// session). The override is a test seam in the codebase's static-seam style
/// (StatusAnnouncer.lastAnnounced, HapticEngine.reset).
class SessionExport {
  SessionExport._();

  @visibleForTesting
  static Future<ShareResult> Function(String path)? overrideShare;

  @visibleForTesting
  static void reset() => overrideShare = null;

  static Future<ShareResult> share(String path) {
    final override = overrideShare;
    if (override != null) return override(path);
    return SharePlus.instance.share(ShareParams(
      files: [XFile(path)],
      subject: 'HapticWay WoZ session log',
    ));
  }
}
