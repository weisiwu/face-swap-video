import 'package:face_swap_video/main.dart';
import 'package:face_swap_video/features/auth/providers/auth_provider.dart';
import 'package:face_swap_video/features/generation/providers/generation_provider.dart';
import 'package:face_swap_video/features/generation/screens/generation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _buildTestApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => GenerationProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: const FaceSwapApp(),
  );
}

void main() {
  testWidgets(
    'App opens generation screen after splash when not authenticated',
    (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp());

      await tester.pump(const Duration(milliseconds: 3000));

      expect(find.text('爆肝AI'), findsOneWidget);
      expect(find.text('源视频'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);
      expect(find.text('手机号登录 / 注册'), findsNothing);
      expect(find.text('获取验证码'), findsNothing);
    },
  );

  testWidgets('Splash copy remains clearly visible for at least 800ms', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pump(const Duration(milliseconds: 800));

    final copyFinder = find.text('快速换脸');
    expect(copyFinder, findsOneWidget);

    final opacityFinder = find.ancestor(
      of: copyFinder,
      matching: find.byType(Opacity),
    );
    expect(opacityFinder, findsOneWidget);
    final opacity = tester.widget<Opacity>(opacityFinder).opacity;
    expect(opacity, greaterThanOrEqualTo(0.9));
  });

  testWidgets(
    'Unauthenticated user is prompted to login only after tapping generate',
    (WidgetTester tester) async {
      final generationProvider = GenerationProvider()
        ..setVideoPath('/tmp/source.mp4')
        ..setFaceImagePath('/tmp/face.png');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => generationProvider),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
          ],
          child: const FaceSwapApp(showSplashOnLaunch: false),
        ),
      );

      expect(find.text('爆肝AI'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);
      expect(find.text('手机号登录 / 注册'), findsNothing);

      await tester.tap(find.text('一键开始换脸'));
      await tester.pumpAndSettle();

      expect(find.text('手机号登录 / 注册'), findsOneWidget);
      expect(find.text('获取验证码'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-app-logo')), findsOneWidget);
      expect(find.byIcon(Icons.face_retouching_natural_rounded), findsNothing);
      final phoneField = tester.widget<TextField>(
        find.byKey(const ValueKey('auth-phone-field')),
      );
      expect(phoneField.controller?.text, '13800138000');
      expect(find.text('登录 / 注册'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-terms-link')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-privacy-link')), findsOneWidget);
    },
  );

  testWidgets('Send code button shows 60 second countdown', (
    WidgetTester tester,
  ) async {
    final generationProvider = GenerationProvider()
      ..setVideoPath('/tmp/source.mp4')
      ..setFaceImagePath('/tmp/face.png');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => generationProvider),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const FaceSwapApp(showSplashOnLaunch: false),
      ),
    );

    await tester.tap(find.text('一键开始换脸'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-agreement-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('auth-send-code-button')));
    await tester.pump();

    expect(find.text('60秒'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59秒'), findsOneWidget);
  });

  testWidgets(
    'Mock sms login from generate prompt returns to generation screen',
    (WidgetTester tester) async {
      final generationProvider = GenerationProvider()
        ..setVideoPath('/tmp/source.mp4')
        ..setFaceImagePath('/tmp/face.png');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => generationProvider),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
          ],
          child: const FaceSwapApp(showSplashOnLaunch: false),
        ),
      );

      await tester.tap(find.text('一键开始换脸'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-phone-field')),
        '15512345678',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-code-field')),
        '999999',
      );
      await tester.tap(find.byKey(const ValueKey('auth-agreement-checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth-login-button')));
      await tester.pumpAndSettle();

      expect(find.text('爆肝AI'), findsOneWidget);
      expect(find.text('源视频'), findsOneWidget);
      expect(find.text('尾号 5678'), findsOneWidget);
      expect(find.text('手机号登录 / 注册'), findsNothing);
    },
  );

  testWidgets(
    'Generation screen keeps action area, notice, and version sticky at bottom',
    (WidgetTester tester) async {
      final authProvider = AuthProvider();
      await authProvider.loginWithSms(phone: '15512345678', code: '123456');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => GenerationProvider()),
            ChangeNotifierProvider(create: (_) => authProvider),
          ],
          child: const FaceSwapApp(showSplashOnLaunch: false),
        ),
      );

      final stickyFooter = find.byKey(
        const ValueKey('generation-sticky-bottom-footer'),
      );

      expect(stickyFooter, findsOneWidget);
      expect(
        find.descendant(of: stickyFooter, matching: find.text('准备好素材后开始生成')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stickyFooter,
          matching: find.textContaining('仅处理授权素材'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stickyFooter, matching: find.text('v1.5.1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Back exit shows retention dialog when selected material exists and exits only after second confirmation',
    (WidgetTester tester) async {
      var exitCount = 0;
      final generationProvider = GenerationProvider()
        ..setVideoPath('/tmp/source.mp4');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => generationProvider),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
          ],
          child: MaterialApp(
            home: GenerationScreen(onExitApp: () => exitCount++),
          ),
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('确定要退出吗？'), findsOneWidget);
      expect(find.textContaining('已选择的素材'), findsOneWidget);
      expect(exitCount, 0);

      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('确定要退出吗？'), findsNothing);
      expect(exitCount, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认退出'));
      await tester.pumpAndSettle();

      expect(exitCount, 1);
    },
  );
}
