import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/generation_provider.dart';
import 'screens/generation_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => GenerationProvider(),
      child: const FaceSwapApp(),
    ),
  );
}

class FaceSwapApp extends StatelessWidget {
  const FaceSwapApp({super.key});

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
      home: const GenerationScreen(),
    );
  }
}
