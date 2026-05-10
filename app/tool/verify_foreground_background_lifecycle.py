#!/usr/bin/env python3
from pathlib import Path

app_root = Path(__file__).resolve().parents[1]
provider = (app_root / 'lib/providers/generation_provider.dart').read_text()
main = (app_root / 'lib/main.dart').read_text()

checks = [
    (
        'app observes lifecycle changes',
        'WidgetsBindingObserver' in main
        and 'didChangeAppLifecycleState' in main
        and 'setAppLifecycleInBackground' in main,
    ),
    (
        'background mode is lifecycle driven',
        'void setAppLifecycleInBackground(bool isBackground)' in provider
        and '_isAppInBackground' in provider
        and '_hasEnteredBackgroundDuringCurrentRun' in provider,
    ),
    (
        'start generation begins in foreground mode',
        'Future<void> startGeneration() async' in provider
        and '_hasEnteredBackgroundDuringCurrentRun = false;' in provider,
    ),
    (
        'foreground processing text does not claim immediate background mode',
        '服务器后台处理中' not in provider
        and '可切到后台等待通知' not in provider
        and '保持前台可查看进度' in provider,
    ),
    (
        'background processing text only appears in lifecycle transition',
        '应用已切到后台，继续后台转换' in provider
        and provider.index('应用已切到后台，继续后台转换') > provider.index('setAppLifecycleInBackground'),
    ),
    (
        'notifications only fire while app is actually backgrounded',
        'if (_isAppInBackground) {' in provider
        and 'NotificationService.showGenerationCompleted' in provider
        and 'NotificationService.showGenerationFailed' in provider,
    ),
]

failed = [name for name, ok in checks if not ok]
if failed:
    print('FAILED checks:')
    for name in failed:
        print(f'- {name}')
    raise SystemExit(1)
print('All foreground/background lifecycle checks passed.')
