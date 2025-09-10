import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status == PermissionStatus.granted;
  }

  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  static Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status == PermissionStatus.granted;
  }

  static Future<bool> checkCameraPermission() async {
    return await Permission.camera.isGranted;
  }

  static Future<bool> checkMicrophonePermission() async {
    return await Permission.microphone.isGranted;
  }

  static Future<Map<String, bool>> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
    ].request();

    return {
      'camera': statuses[Permission.camera] == PermissionStatus.granted,
      'microphone': statuses[Permission.microphone] == PermissionStatus.granted,
      'storage': statuses[Permission.storage] == PermissionStatus.granted,
    };
  }
}