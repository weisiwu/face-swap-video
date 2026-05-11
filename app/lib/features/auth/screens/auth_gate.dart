import 'package:flutter/material.dart';

import 'package:face_swap_video/features/generation/screens/generation_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return const GenerationScreen(key: ValueKey('generation'));
  }
}
