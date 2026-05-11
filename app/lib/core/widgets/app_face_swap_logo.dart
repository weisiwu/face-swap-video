import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppFaceSwapLogo extends StatelessWidget {
  const AppFaceSwapLogo({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: AppFaceSwapLogoPainter()),
    );
  }
}

class AppFaceSwapLogoPainter extends CustomPainter {
  const AppFaceSwapLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pink = const Color(0xFFFF7ACD);
    final cyan = const Color(0xFF72F2FF);
    final violet = const Color(0xFF8B5CF6);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          pink.withValues(alpha: 0.32),
          cyan.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, size.width * 0.42, glowPaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.42),
      -math.pi * 0.12,
      math.pi * 1.25,
      false,
      orbitPaint..color = cyan.withValues(alpha: 0.68),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.34),
      math.pi * 1.04,
      -math.pi * 1.18,
      false,
      orbitPaint..color = pink.withValues(alpha: 0.75),
    );

    final left = Offset(size.width * 0.53, size.height * 0.5);
    final right = Offset(size.width * 0.47, size.height * 0.5);
    _drawAnimeFace(canvas, left, size.width * 0.19, pink, 0.08);
    _drawAnimeFace(canvas, right, size.width * 0.19, cyan, -0.08);

    final sparkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = violet.withValues(alpha: 0.78);
    for (var i = 0; i < 6; i++) {
      final angle = math.pi * 2 + i * math.pi / 3;
      final r = size.width * (0.23 + 0.12 * ((i % 2) + 1) / 2);
      final p = center + Offset(math.cos(angle), math.sin(angle)) * r;
      canvas.drawCircle(p, 2.1, sparkPaint);
    }
  }

  void _drawAnimeFace(
    Canvas canvas,
    Offset c,
    double r,
    Color color,
    double tilt,
  ) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    final facePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFF6F8);
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.9);
    final hairPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.82);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: r * 1.65, height: r * 1.82),
        Radius.circular(r * 0.72),
      ),
      facePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: r * 1.65, height: r * 1.82),
        Radius.circular(r * 0.72),
      ),
      edgePaint,
    );
    final hair = Path()
      ..moveTo(-r * 0.82, -r * 0.2)
      ..quadraticBezierTo(-r * 0.55, -r * 1.0, 0, -r * 0.9)
      ..quadraticBezierTo(r * 0.65, -r * 0.92, r * 0.82, -r * 0.1)
      ..quadraticBezierTo(r * 0.28, -r * 0.34, -r * 0.1, -r * 0.22)
      ..quadraticBezierTo(-r * 0.45, -r * 0.08, -r * 0.82, -r * 0.2)
      ..close();
    canvas.drawPath(hair, hairPaint);

    final eyePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF17111F);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.28, r * 0.08),
        width: r * 0.18,
        height: r * 0.34,
      ),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(r * 0.28, r * 0.08),
        width: r * 0.18,
        height: r * 0.34,
      ),
      eyePaint,
    );
    canvas.drawCircle(
      Offset(-r * 0.24, -r * 0.02),
      r * 0.035,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(r * 0.32, -r * 0.02),
      r * 0.035,
      Paint()..color = Colors.white,
    );
    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF17111F).withValues(alpha: 0.55);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(0, r * 0.34),
        width: r * 0.34,
        height: r * 0.18,
      ),
      0,
      math.pi,
      false,
      mouth,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AppFaceSwapLogoPainter oldDelegate) => false;
}
