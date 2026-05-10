#!/usr/bin/env python3
from pathlib import Path

app_root = Path(__file__).resolve().parents[1]
main = (app_root / 'lib/main.dart').read_text()
generation = (app_root / 'lib/screens/generation_screen.dart').read_text()
splash_path = app_root / 'lib/screens/splash_screen.dart'
splash = splash_path.read_text() if splash_path.exists() else ''

checks = [
    ('animated splash screen exists', splash_path.exists() and 'AnimeFaceSwapSplashScreen' in splash),
    ('splash uses vector custom painter animation', 'CustomPainter' in splash and 'AnimationController' in splash and '_FaceSwapMarkPainter' in splash),
    ('splash expresses fast face swap', '快速换脸' in splash and 'Curves.easeInOutCubic' in splash and 'drawArc' in splash),
    ('main launches splash before generation screen', "import 'screens/splash_screen.dart';" in main and 'AnimeFaceSwapSplashScreen' in main and 'onFinished:' in main),
    ('modern dark anime palette applied', 'Color(0xFF050510)' in generation and 'Color(0xFFFF7ACD)' in generation and 'Color(0xFF72F2FF)' in generation),
    ('background has custom anime aura painter', '_AnimeAuraPainter' in generation and 'CustomPaint' in generation),
    ('hero has face swap illustration', '_FaceSwapHeroMark' in generation and '_AnimeFaceAvatar' in generation),
    ('selection cards use modern glass style', 'BackdropFilter' in generation and '_buildSelectionCard' in generation and 'BlendMode.plus' in generation),
    ('workflow chips exist', '1 上传视频' in generation and '2 选择人脸' in generation and '3 AI 换脸' in generation),
    ('CTA copy is modernized', '一键开始换脸' in generation and '准备好素材后开始生成' in generation),
    ('version footer exists', "const String _appVersion = '1.0.0';" in generation and "'v$_appVersion'" in generation and '_buildVersionFooter()' in generation),
]

failed = [name for name, ok in checks if not ok]
if failed:
    print('FAILED checks:')
    for name in failed:
        print(f'- {name}')
    raise SystemExit(1)
print('All modern anime UI checks passed.')
