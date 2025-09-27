import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<bool> requestAudioPermissions() async {
    final micPermission = await Permission.microphone.request();

    return micPermission == PermissionStatus.granted;
  }

  static Future<bool> hasAudioPermissions() async {
    final micStatus = await Permission.microphone.status;
    return micStatus == PermissionStatus.granted;
  }

  static Future<bool> requestPhoneStatePermission() async {
    final phonePermission = await Permission.phone.request();
    return phonePermission == PermissionStatus.granted;
  }

  static Future<bool> hasPhoneStatePermission() async {
    final phoneStatus = await Permission.phone.status;
    return phoneStatus == PermissionStatus.granted;
  }

  static Future<bool> requestNotificationPermission() async {
    final permission = await Permission.notification.request();
    return permission == PermissionStatus.granted;
  }

  static Future<bool> requestAllPermissions() async {
    final micPermission = await Permission.microphone.request();
    final phonePermission = await Permission.phone.request();
    final notificationPermission = await Permission.notification.request();

    return micPermission == PermissionStatus.granted &&
        phonePermission == PermissionStatus.granted &&
        notificationPermission == PermissionStatus.granted;
  }
}
