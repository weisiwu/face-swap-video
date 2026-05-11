import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:face_swap_video/core/services/app_logger.dart';
import 'package:face_swap_video/features/auth/services/auth_session_store.dart';
import 'package:face_swap_video/features/auth/services/device_phone_service.dart';

const String _logTag = 'AuthProvider';

String _maskPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '<empty>';
  if (phone.length < 4) return '***';
  return '***${phone.substring(phone.length - 4)}';
}

class AuthProvider extends ChangeNotifier {
  static const String mockDevicePhone = '13800138000';

  AuthProvider({
    DevicePhoneService? devicePhoneService,
    AuthSessionStore? sessionStore,
    String? initialSuggestedPhone,
  }) : _devicePhoneService = devicePhoneService,
       _sessionStore = sessionStore ?? SharedPreferencesAuthSessionStore(),
       _suggestedPhone =
           initialSuggestedPhone ?? (kDebugMode ? mockDevicePhone : '') {
    unawaited(loadSavedSession());
  }

  final DevicePhoneService? _devicePhoneService;
  final AuthSessionStore _sessionStore;

  bool _isAuthenticated = false;
  String? _phone;
  String _suggestedPhone;
  bool _isLoadingSuggestedPhone = false;
  bool _isSendingCode = false;
  bool _isLoggingIn = false;
  int _codeCountdownSeconds = 0;
  int _sessionVersion = 0;
  Timer? _codeCountdownTimer;

  bool get isAuthenticated => _isAuthenticated;
  String? get phone => _phone;
  bool get isLoadingSuggestedPhone => _isLoadingSuggestedPhone;
  bool get isSendingCode => _isSendingCode;
  bool get isLoggingIn => _isLoggingIn;
  String get suggestedPhone => _suggestedPhone;
  int get codeCountdownSeconds => _codeCountdownSeconds;
  bool get canSendCode => !_isSendingCode && _codeCountdownSeconds == 0;

  String get displayPhone {
    final currentPhone = _phone;
    if (!_isAuthenticated || currentPhone == null || currentPhone.length < 4) {
      return '未登录';
    }
    return '尾号 ${currentPhone.substring(currentPhone.length - 4)}';
  }

  Future<void> loadSavedSession() async {
    final loadVersion = _sessionVersion;
    final session = await _sessionStore.load();
    if (loadVersion != _sessionVersion || session == null) {
      appLogger.i(_logTag, 'loadSavedSession none');
      return;
    }

    _phone = session.phone;
    _isAuthenticated = true;
    appLogger.i(
      _logTag,
      'loadSavedSession restored phone=${_maskPhone(session.phone)}',
    );
    notifyListeners();
  }

  Future<void> loadSuggestedPhone() async {
    if (_isLoadingSuggestedPhone) return;

    appLogger.i(_logTag, 'loadSuggestedPhone start');
    _isLoadingSuggestedPhone = true;
    notifyListeners();
    final detectedPhone = await (_devicePhoneService ?? DevicePhoneService())
        .getPrimarySimPhoneNumber();
    _isLoadingSuggestedPhone = false;

    if (detectedPhone != null && detectedPhone.isNotEmpty) {
      _suggestedPhone = detectedPhone;
      appLogger.i(
        _logTag,
        'loadSuggestedPhone detected phone=${_maskPhone(detectedPhone)}',
      );
    } else {
      appLogger.i(_logTag, 'loadSuggestedPhone no SIM phone detected');
    }
    notifyListeners();
  }

  Future<void> sendCode(String phone) async {
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) {
      throw ArgumentError('请输入手机号');
    }
    if (!canSendCode) {
      return;
    }

    appLogger.i(_logTag, 'sendCode phone=${_maskPhone(normalizedPhone)}');
    _isSendingCode = true;
    notifyListeners();
    _isSendingCode = false;
    _startCodeCountdown();
    notifyListeners();
  }

  void _startCodeCountdown() {
    _codeCountdownTimer?.cancel();
    _codeCountdownSeconds = 60;
    _codeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapseCodeCountdown(const Duration(seconds: 1));
    });
  }

  void _elapseCodeCountdown(Duration elapsed) {
    if (_codeCountdownSeconds <= 0) return;
    _codeCountdownSeconds = (_codeCountdownSeconds - elapsed.inSeconds).clamp(
      0,
      60,
    );
    if (_codeCountdownSeconds == 0) {
      _codeCountdownTimer?.cancel();
      _codeCountdownTimer = null;
    }
    notifyListeners();
  }

  @visibleForTesting
  void debugElapseCodeCountdown(Duration elapsed) {
    _elapseCodeCountdown(elapsed);
  }

  Future<void> loginWithSms({
    required String phone,
    required String code,
  }) async {
    final normalizedPhone = phone.trim();
    final normalizedCode = code.trim();
    if (normalizedPhone.isEmpty) {
      throw ArgumentError('请输入手机号');
    }
    if (normalizedCode.isEmpty) {
      throw ArgumentError('请输入验证码');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedCode)) {
      throw ArgumentError('请输入6位数字验证码');
    }

    appLogger.i(
      _logTag,
      'loginWithSms start phone=${_maskPhone(normalizedPhone)}',
    );
    _isLoggingIn = true;
    notifyListeners();
    _sessionVersion++;
    _phone = normalizedPhone;
    _isAuthenticated = true;
    try {
      await _sessionStore.save(AuthSession(phone: normalizedPhone));
      appLogger.i(
        _logTag,
        'loginWithSms success phone=${_maskPhone(normalizedPhone)}',
      );
    } catch (error, stack) {
      appLogger.e(_logTag, 'loginWithSms session save failed', error, stack);
      rethrow;
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    appLogger.i(_logTag, 'logout phone=${_maskPhone(_phone)}');
    _sessionVersion++;
    _phone = null;
    _isAuthenticated = false;
    _isSendingCode = false;
    _isLoggingIn = false;
    await _sessionStore.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _codeCountdownTimer?.cancel();
    super.dispose();
  }
}
