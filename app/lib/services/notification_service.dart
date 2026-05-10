import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'generation_status',
    '生成状态',
    description: '视频换脸处理完成或失败时提醒',
    importance: Importance.high,
  );

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);
    if (Platform.isAndroid) {
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  static Future<void> showGenerationCompleted() {
    return _show(id: 1001, title: '视频换脸已完成', body: '处理后的视频已经准备好，点开 App 预览并保存。');
  }

  static Future<void> showGenerationFailed(String message) {
    return _show(
      id: 1002,
      title: '视频换脸失败',
      body: message.isEmpty ? '处理失败，请回到 App 后重试。' : message,
    );
  }

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) {
    return _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.status,
          ticker: title,
        ),
      ),
    );
  }
}
