import 'package:face_swap_video/features/auth/providers/auth_provider.dart';
import 'package:face_swap_video/features/auth/services/device_phone_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('test/device_phone');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('mock sms auth accepts any non-empty phone and code', () async {
    final provider = AuthProvider();

    await provider.sendCode('13800138000');
    await provider.loginWithSms(phone: '13800138000', code: '000000');

    expect(provider.isAuthenticated, isTrue);
    expect(provider.phone, '13800138000');
    expect(provider.displayPhone, '尾号 8000');
  });

  test('mock sms auth requires exactly six digit code', () async {
    final provider = AuthProvider();

    expect(
      () => provider.loginWithSms(phone: '13800138000', code: '12345'),
      throwsArgumentError,
    );
    expect(
      () => provider.loginWithSms(phone: '13800138000', code: '1234567'),
      throwsArgumentError,
    );
    expect(
      () => provider.loginWithSms(phone: '13800138000', code: '12ab56'),
      throwsArgumentError,
    );

    await provider.loginWithSms(phone: '13800138000', code: '123456');

    expect(provider.isAuthenticated, isTrue);
  });

  test('prefills debug mock phone before device number is detected', () {
    final provider = AuthProvider();

    expect(provider.suggestedPhone, '13800138000');
  });

  test(
    'loads primary sim phone as suggested phone and normalizes country code',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getPrimarySimPhoneNumber');
            return '+86 155 1234 5678';
          });

      final provider = AuthProvider(
        devicePhoneService: DevicePhoneService(channel: channel),
      );

      await provider.loadSuggestedPhone();

      expect(provider.suggestedPhone, '15512345678');
    },
  );

  test('keeps existing suggestion when device phone is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final provider = AuthProvider(
      devicePhoneService: DevicePhoneService(channel: channel),
      initialSuggestedPhone: '16600001111',
    );

    await provider.loadSuggestedPhone();

    expect(provider.suggestedPhone, '16600001111');
  });

  test('send code starts 60 second countdown and can elapse', () async {
    final provider = AuthProvider();

    await provider.sendCode('13800138000');

    expect(provider.codeCountdownSeconds, 60);
    expect(provider.canSendCode, isFalse);

    provider.debugElapseCodeCountdown(const Duration(seconds: 1));
    expect(provider.codeCountdownSeconds, 59);

    provider.debugElapseCodeCountdown(const Duration(seconds: 59));
    expect(provider.codeCountdownSeconds, 0);
    expect(provider.canSendCode, isTrue);
  });

  test('logout clears mock auth state', () async {
    final provider = AuthProvider();

    await provider.loginWithSms(phone: '19999999999', code: '123456');
    provider.logout();

    expect(provider.isAuthenticated, isFalse);
    expect(provider.phone, isNull);
    expect(provider.displayPhone, '未登录');
  });
}
