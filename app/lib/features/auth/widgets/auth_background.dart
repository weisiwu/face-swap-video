import 'package:flutter/material.dart';

class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.8),
          radius: 1.1,
          colors: [
            const Color(0xFF7C3AED).withValues(alpha: 0.22),
            const Color(0xFF050510),
          ],
        ),
      ),
    );
  }
}
