import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:face_swap_video/features/auth/providers/auth_provider.dart';
import 'package:face_swap_video/features/generation/providers/generation_provider.dart';
import 'package:face_swap_video/features/auth/screens/auth_gate.dart';
import 'package:face_swap_video/core/screens/splash_screen.dart';
import 'package:face_swap_video/core/services/app_logger.dart';
import 'package:face_swap_video/core/services/notification_service.dart';
import 'package:face_swap_video/core/utils/app_lifecycle_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.init();
  appLogger.i('App', 'app starting up');
  await NotificationService.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GenerationProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const FaceSwapApp(),
    ),
  );
}

class FaceSwapApp extends StatefulWidget {
  const FaceSwapApp({super.key, this.showSplashOnLaunch = true});

  final bool showSplashOnLaunch;

  @override
  State<FaceSwapApp> createState() => _FaceSwapAppState();
}

class _FaceSwapAppState extends State<FaceSwapApp> with WidgetsBindingObserver {
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _showSplash = widget.showSplashOnLaunch;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final isBackground = isBackgroundLifecycleState(state);
    appLogger.i('App', 'lifecycle state=$state isBackground=$isBackground');
    context.read<GenerationProvider>().setAppLifecycleInBackground(
      isBackground,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '爆肝AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'System',
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 620),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _buildHomeTransition,
        child: _showSplash
            ? AnimeFaceSwapSplashScreen(
                key: const ValueKey('splash'),
                onFinished: () {
                  if (!mounted) return;
                  setState(() => _showSplash = false);
                },
              )
            : const AuthGate(key: ValueKey('auth-gate')),
      ),
    );
  }

  Widget _buildHomeTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(opacity: curved, child: child);
  }
}
