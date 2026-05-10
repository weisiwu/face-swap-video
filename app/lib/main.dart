import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/generation_provider.dart';
import 'screens/generation_screen.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => GenerationProvider(),
      child: const FaceSwapApp(),
    ),
  );
}

class FaceSwapApp extends StatefulWidget {
  const FaceSwapApp({super.key});

  @override
  State<FaceSwapApp> createState() => _FaceSwapAppState();
}

class _FaceSwapAppState extends State<FaceSwapApp> with WidgetsBindingObserver {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
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
    final isBackground = switch (state) {
      AppLifecycleState.paused ||
      AppLifecycleState.detached ||
      AppLifecycleState.hidden => true,
      AppLifecycleState.resumed || AppLifecycleState.inactive => false,
    };
    context.read<GenerationProvider>().setAppLifecycleInBackground(
      isBackground,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '视频换脸',
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
            : const GenerationScreen(key: ValueKey('generation')),
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
