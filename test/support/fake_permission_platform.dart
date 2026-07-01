import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Test double for [PermissionHandlerPlatform] — returns a canned status
/// instead of prompting a real OS permission dialog. Install with
/// `PermissionHandlerPlatform.instance = FakePermissionHandlerPlatform()`.
class FakePermissionHandlerPlatform extends PermissionHandlerPlatform {
  PermissionStatus statusToReturn = PermissionStatus.granted;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      statusToReturn;

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatus.enabled;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    return {for (final p in permissions) p: statusToReturn};
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async =>
      false;
}
