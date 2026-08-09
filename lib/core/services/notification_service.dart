import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // ✅ Callback for notification taps (set from main.dart)
  void Function(NotificationResponse)? onNotificationTap;

  Future<void> init() async {
    if (_isInitialized) return;

    final androidSettings =
        const AndroidInitializationSettings('@mipmap/launcher_icon');
    final iosSettings = const DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked with payload: ${response.payload}');
        // ✅ Forward to the app-defined callback
        onNotificationTap?.call(response);
      },
    );

    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
            
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    _isInitialized = true;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'allo_zhen_messages',
      'Messages',
      channelDescription: 'Notifications for incoming messages on Allo Zhen',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentSound: true),
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await showNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  // ✅ Cancel a specific notification by ID (e.g., when chat is opened)
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  // ✅ Cancel ALL notifications (good for logout/clear all)
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}