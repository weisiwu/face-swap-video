#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
screen = (root / 'lib/screens/generation_screen.dart').read_text()
pubspec = (root / 'pubspec.yaml').read_text()

checks = {
    'completion dialog exists': '_showCompletionDialog' in screen and '换脸完成！' in screen,
    'save result implementation exists': '_saveResultVideo' in screen and 'PhotoManager.editor.saveVideo' in screen,
    'save success prompt exists': '_showSaveSuccessDialog' in screen and '保存成功' in screen,
    'share button removed': "label: '分享'" not in screen and "Icons.share_rounded" not in screen,
    'retry-again button removed': "label: '再来一次'" not in screen and "Icons.refresh_rounded" not in screen,
    'video thumbnail dependency declared': 'video_thumbnail:' in pubspec,
    'source video thumbnail displayed': 'VideoThumbnail.thumbnailData' in screen and 'source-video-thumb' in screen,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} {name}")
if failed:
    raise SystemExit(f"Missing expected UI behavior: {', '.join(failed)}")
