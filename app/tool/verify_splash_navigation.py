#!/usr/bin/env python3
from pathlib import Path

app_root = Path(__file__).resolve().parents[1]
main = (app_root / 'lib/main.dart').read_text()
splash = (app_root / 'lib/screens/splash_screen.dart').read_text()

checks = [
    ('main keeps splash state flag', 'bool _showSplash = true;' in main),
    ('splash completion switches state instead of using parent Navigator context', 'setState(() => _showSplash = false)' in main),
    ('home conditionally shows splash then generation screen', '_showSplash' in main and 'const GenerationScreen()' in main and 'AnimeFaceSwapSplashScreen' in main),
    ('main does not call Navigator.of(context) from FaceSwapApp build callback', 'Navigator.of(context).pushReplacement' not in main),
    ('splash invokes onFinished when animation completes', 'AnimationStatus.completed' in splash and 'widget.onFinished()' in splash),
]

failed = [name for name, ok in checks if not ok]
if failed:
    print('FAILED checks:')
    for name in failed:
        print(f'- {name}')
    raise SystemExit(1)
print('All splash navigation checks passed.')
