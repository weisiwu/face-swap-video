import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:face_swap_video/features/auth/services/auth_session_store.dart';
import 'package:face_swap_video/features/auth/services/device_phone_service.dart';

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
    if (loadVersion != _sessionVersion || session == null) return;

    _phone = session.phone;
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> loadSuggestedPhone() async {
    if (_isLoadingSuggestedPhone) return;

    _isLoadingSuggestedPhone = true;
    notifyListeners();
    final detectedPhone = await (_devicePhoneService ?? DevicePhoneService())
        .getPrimarySimPhoneNumber();
    _isLoadingSuggestedPhone = false;

    if (detectedPhone != null && detectedPhone.isNotEmpty) {
      _suggestedPhone = detectedPhone;
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

    _isLoggingIn = true;
    notifyListeners();
    _sessionVersion++;
    _phone = normalizedPhone;
    _isAuthenticated = true;
    await _sessionStore.save(AuthSession(phone: normalizedPhone));
    _isLoggingIn = false;
    notifyListeners();
  }

  Future<void> logout() async {
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
