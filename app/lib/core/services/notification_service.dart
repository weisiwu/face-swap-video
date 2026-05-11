import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:face_swap_video/core/services/app_logger.dart';

const String _logTag = 'NotificationService';

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
    appLogger.i(_logTag, 'initialize start');
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);
    try {
      await _plugin.initialize(settings: settings);

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_channel);
      appLogger.i(_logTag, 'initialize done channel=${_channel.id}');
    } catch (error, stack) {
      appLogger.e(_logTag, 'initialize failed', error, stack);
    }
  }

  static Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> showGenerationCompleted() {
    appLogger.i(_logTag, 'showGenerationCompleted');
    return _show(id: 1001, title: '视频换脸已完成', body: '处理后的视频已经准备好，点开 App 预览并保存。');
  }

  static Future<void> showGenerationFailed(String message) {
    appLogger.w(_logTag, 'showGenerationFailed message=$message');
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
  }) async {
    try {
      await _ensureNotificationPermission();
    } catch (error, stack) {
      appLogger.w(_logTag, 'permission check failed', error, stack);
    }
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
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
