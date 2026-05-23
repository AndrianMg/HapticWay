import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  static Future<bool> isCameraGranted() async =>
      (await Permission.camera.status).isGranted;

  static Future<bool> requestCamera() async =>
      (await Permission.camera.request()).isGranted;
}
