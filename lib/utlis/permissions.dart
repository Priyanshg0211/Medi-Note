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
  
  static Future<bool> requestNotificationPermission() async {
    final permission = await Permission.notification.request();
    return permission == PermissionStatus.granted;
  }
}