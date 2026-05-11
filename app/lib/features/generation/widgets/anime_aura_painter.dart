import 'package:flutter/material.dart';

class AnimeAuraPainter extends CustomPainter {
  const AnimeAuraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF050510), Color(0xFF171126), Color(0xFF050510)],
        ).createShader(rect),
    );

    void glow(Offset center, double radius, Color color) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.24), Colors.transparent],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    glow(
      Offset(size.width * 0.18, size.height * 0.10),
      size.width * 0.58,
      const Color(0xFFFF7ACD),
    );
    glow(
      Offset(size.width * 0.88, size.height * 0.28),
      size.width * 0.48,
      const Color(0xFF72F2FF),
    );
    glow(
      Offset(size.width * 0.50, size.height * 0.92),
      size.width * 0.60,
      const Color(0xFF8B5CF6),
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.035);
    for (var y = 0.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 20), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant AnimeAuraPainter oldDelegate) => false;
}
