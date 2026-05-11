import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:face_swap_video/core/widgets/face_swap_mark_painter.dart';

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

  double _copyOpacity(double t) {
    // 文案在 800ms 前保持完整可读；淡入/淡出本身保持轻快。
    const totalMs = 2200.0;
    const fadeInMs = 180.0;
    const holdUntilMs = 800.0;
    const fadeOutMs = 220.0;

    final fadeIn = Curves.easeOutCubic.transform(
      (t / (fadeInMs / totalMs)).clamp(0.0, 1.0),
    );
    final fadeOut =
        1 -
        Curves.easeInCubic.transform(
          ((t - holdUntilMs / totalMs) / (fadeOutMs / totalMs)).clamp(0.0, 1.0),
        );
    return (fadeIn * fadeOut).clamp(0.0, 1.0);
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
                  final copyOpacity = _copyOpacity(t);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: logoTop,
                        left: (constraints.maxWidth - logoSize) / 2,
                        width: logoSize,
                        height: logoSize,
                        child: CustomPaint(
                          painter: FaceSwapMarkPainter(progress: t),
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
