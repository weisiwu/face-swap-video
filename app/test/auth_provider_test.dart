import 'package:face_swap_video/features/auth/providers/auth_provider.dart';
import 'package:face_swap_video/features/auth/services/auth_session_store.dart';
import 'package:face_swap_video/features/auth/services/device_phone_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('test/device_phone');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

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
    await provider.logout();

    expect(provider.isAuthenticated, isFalse);
    expect(provider.phone, isNull);
    expect(provider.displayPhone, '未登录');
  });

  test('loads saved session from local app storage', () async {
    final store = _FakeAuthSessionStore(
      initialSession: const AuthSession(phone: '17700008888'),
    );
    final provider = AuthProvider(sessionStore: store);

    await provider.loadSavedSession();

    expect(provider.isAuthenticated, isTrue);
    expect(provider.phone, '17700008888');
    expect(provider.displayPhone, '尾号 8888');
  });

  test('persists login locally and clears it on logout', () async {
    final store = _FakeAuthSessionStore();
    final provider = AuthProvider(sessionStore: store);

    await provider.loginWithSms(phone: '18800009999', code: '123456');

    expect(store.savedSession?.phone, '18800009999');

    await provider.logout();

    expect(store.savedSession, isNull);
    expect(provider.isAuthenticated, isFalse);
  });
}

class _FakeAuthSessionStore implements AuthSessionStore {
  _FakeAuthSessionStore({AuthSession? initialSession})
    : savedSession = initialSession;

  AuthSession? savedSession;

  @override
  Future<AuthSession?> load() async => savedSession;

  @override
  Future<void> save(AuthSession session) async {
    savedSession = session;
  }

  @override
  Future<void> clear() async {
    savedSession = null;
  }
}
