import 'package:flutter/services.dart';

class DevicePhoneService {
  DevicePhoneService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName =
      'com.baoganai.face_swap_video/device_phone';

  final MethodChannel _channel;

  Future<String?> getPrimarySimPhoneNumber() async {
    try {
      final phone = await _channel.invokeMethod<String>(
        'getPrimarySimPhoneNumber',
      );
      final normalized = _normalizePhone(phone);
      return normalized.isEmpty ? null : normalized;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  String _normalizePhone(String? phone) {
    final value = phone?.trim() ?? '';
    if (value.isEmpty) return '';

    var normalized = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.startsWith('+86') && normalized.length == 14) {
      normalized = normalized.substring(3);
    } else if (normalized.startsWith('86') && normalized.length == 13) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }
}
