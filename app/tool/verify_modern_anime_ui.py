#!/usr/bin/env python3
from pathlib import Path

app_root = Path(__file__).resolve().parents[1]
main = (app_root / 'lib/main.dart').read_text()
generation = (app_root / 'lib/screens/generation_screen.dart').read_text()
splash_path = app_root / 'lib/screens/splash_screen.dart'
splash = splash_path.read_text() if splash_path.exists() else ''
styles = (app_root / 'android/app/src/main/res/values/styles.xml').read_text()
styles_v31 = (app_root / 'android/app/src/main/res/values-v31/styles.xml').read_text()
launch_background = (app_root / 'android/app/src/main/res/drawable/launch_background.xml').read_text()

checks = [
    ('animated splash screen exists', splash_path.exists() and 'AnimeFaceSwapSplashScreen' in splash),
    ('splash uses vector custom painter animation', 'CustomPainter' in splash and 'AnimationController' in splash and '_FaceSwapMarkPainter' in splash),
    ('splash expresses fast face swap', '快速换脸' in splash and 'Curves.easeInOutCubic' in splash and 'drawArc' in splash),
    ('splash logo aligns to measured launch red-box Y axis', '_targetFaceTopPhysicalPx = 253' in splash and '_targetLogoTop(context)' in splash and 'logoTop' in splash),
    ('main launches splash before generation screen', "import 'screens/splash_screen.dart';" in main and 'AnimeFaceSwapSplashScreen' in main and 'onFinished:' in main),
    ('main reveals generation screen with aligned fade transition after splash', 'AnimatedSwitcher' in main and '_buildHomeTransition' in main and 'FadeTransition' in main and 'ScaleTransition' not in main and 'SlideTransition' not in main),
    ('modern dark anime palette applied', 'Color(0xFF050510)' in generation and 'Color(0xFFFF7ACD)' in generation and 'Color(0xFF72F2FF)' in generation),
    ('background has custom anime aura painter', '_AnimeAuraPainter' in generation and 'CustomPaint' in generation),
    ('hero has compact frameless logo only without title', '_HomeFaceSwapLogo(size: 92)' in generation and "'视频换脸'," not in generation and 'Widget _buildHeader() {' in generation and 'return const Center(child: _HomeFaceSwapLogo(size: 92));' in generation),
    ('header intro copy removed', "'极简动漫风 · 快速生成 · 前台实时进度'" not in generation),
    ('home logo matches splash final painter and uses measured top inset', '_HomeFaceSwapLogo' in generation and 'CustomPaint(painter: _HomeFaceSwapLogoPainter())' in generation and '_targetLogoTopInset(context)' in generation and 'const SizedBox(height: 14)' in generation),
    ('home content is top-aligned so logo does not drop after splash', 'alignment: Alignment.topCenter' in generation and 'child: Center(\n                child: ConstrainedBox' not in generation),
    ('native launch screen is dark and empty instead of white', '@color/launch_background' in styles and '@color/launch_background' in launch_background and 'windowSplashScreenBackground' in styles_v31 and 'empty_splash_icon' in styles_v31),
    ('selection cards use modern glass style', 'BackdropFilter' in generation and '_buildSelectionCard' in generation and 'BlendMode.plus' in generation),
    ('workflow chips exist', '1 上传视频' in generation and '2 选择人脸' in generation and '3 AI 换脸' in generation),
    ('CTA copy is modernized', '一键开始换脸' in generation and '准备好素材后开始生成' in generation),
    ('version footer exists', "const String _appVersion = '1.3.2';" in generation and "'v$_appVersion'" in generation and '_buildVersionFooter()' in generation),
]

failed = [name for name, ok in checks if not ok]
if failed:
    print('FAILED checks:')
    for name in failed:
        print(f'- {name}')
    raise SystemExit(1)
print('All modern anime UI checks passed.')
