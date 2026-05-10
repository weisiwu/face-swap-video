import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class AnimeFaceSwapSplashScreen extends StatefulWidget {
  const AnimeFaceSwapSplashScreen({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<AnimeFaceSwapSplashScreen> createState() =>
      _AnimeFaceSwapSplashScreenState();
}

class _AnimeFaceSwapSplashScreenState extends State<AnimeFaceSwapSplashScreen>
    with SingleTickerProviderStateMixin {
  static const double _homeLogoSize = 92;
  static const double _targetFaceTopPhysicalPx = 134;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _exitProgress(double t) {
    // logo 需要从页面中间移动到顶部，但必须在切到主屏前足够早完成。
    // 真机截图验证 1800ms/1900ms/2000ms 必须保持同一 Y 轴，
    // 所以把移动段放在开屏前半段：约 220ms 开始，约 1320ms 完成，
    // 之后保持在主屏目标位置直到进入主屏。
    return Curves.easeInOutCubic.transform(((t - 0.10) / 0.50).clamp(0.0, 1.0));
  }

  double _targetLogoTop(BuildContext context) {
    final media = MediaQuery.of(context);
    final faceTopInsideLogo = _homeLogoSize * (0.5 - 0.19 * 0.91);
    return (_targetFaceTopPhysicalPx / media.devicePixelRatio) -
        media.padding.top -
        faceTopInsideLogo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.15,
            colors: [Color(0xFF211035), Color(0xFF070711), Color(0xFF050510)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeInOutCubic,
                ),
                builder: (context, _) {
                  final t = _controller.value;
                  final exit = _exitProgress(t);
                  final logoSize = ui.lerpDouble(190, 92, exit)!;
                  final startCenterY = constraints.maxHeight * 0.48;
                  // 以真机截图中“开屏最后正确红框”为基准，计算同一物理 Y 轴。
                  // 不再用猜测的 6dp 顶部偏移，避免主屏 logo 相对开屏红框下坠。
                  final homeLogoTop = _targetLogoTop(context);
                  final logoTop = ui.lerpDouble(
                    startCenterY - logoSize / 2,
                    homeLogoTop,
                    exit,
                  )!;
                  final copyTop = ui.lerpDouble(
                    startCenterY + 120,
                    startCenterY + 74,
                    exit,
                  )!;
                  final copyOpacity = (t * 1.4).clamp(0.0, 1.0) * (1 - exit);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: logoTop,
                        left: (constraints.maxWidth - logoSize) / 2,
                        width: logoSize,
                        height: logoSize,
                        child: CustomPaint(
                          painter: _FaceSwapMarkPainter(progress: t),
                        ),
                      ),
                      Positioned(
                        top: copyTop,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: copyOpacity,
                            child: Transform.translate(
                              offset: Offset(0, 16 * (1 - t)),
                              child: const Column(
                                children: [
                                  Text(
                                    '快速换脸',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '一闪之间，换上新面孔',
                                    style: TextStyle(
                                      color: Color(0x99FFFFFF),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FaceSwapMarkPainter extends CustomPainter {
  const _FaceSwapMarkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pink = const Color(0xFFFF7ACD);
    final cyan = const Color(0xFF72F2FF);
    final violet = const Color(0xFF8B5CF6);
    final swap = Curves.easeInOutCubic.transform(progress);
    final pulse = math.sin(progress * math.pi);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          pink.withValues(alpha: 0.28 + pulse * 0.16),
          cyan.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, size.width * (0.38 + pulse * 0.06), glowPaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.42),
      -math.pi * 0.12,
      math.pi * 1.25 * swap,
      false,
      orbitPaint..color = cyan.withValues(alpha: 0.65),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.34),
      math.pi * 1.04,
      -math.pi * 1.18 * swap,
      false,
      orbitPaint..color = pink.withValues(alpha: 0.72),
    );

    final left = Offset(size.width * (0.34 + 0.19 * swap), size.height * 0.5);
    final right = Offset(size.width * (0.66 - 0.19 * swap), size.height * 0.5);
    _drawAnimeFace(canvas, left, size.width * 0.19, pink, -0.08 + swap * 0.16);
    _drawAnimeFace(canvas, right, size.width * 0.19, cyan, 0.08 - swap * 0.16);

    final sparkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = violet.withValues(alpha: 0.9 * pulse);
    for (var i = 0; i < 6; i++) {
      final angle = progress * math.pi * 2 + i * math.pi / 3;
      final r = size.width * (0.23 + 0.12 * ((i % 2) + 1) / 2);
      final p = center + Offset(math.cos(angle), math.sin(angle)) * r;
      canvas.drawCircle(p, 2.2 + pulse * 1.4, sparkPaint);
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
      ..strokeWidth = 2.2
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
      ..strokeWidth = 1.8
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
  bool shouldRepaint(covariant _FaceSwapMarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
