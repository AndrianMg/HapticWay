import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Test double for [PathProviderPlatform] — points the app documents
/// directory at a test-owned temp dir. Install with
/// `PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path)`
/// in setUp.
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
