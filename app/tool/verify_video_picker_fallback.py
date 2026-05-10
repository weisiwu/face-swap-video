#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
screen = (root / 'lib/screens/video_grid_screen.dart').read_text()

checks = {
    'file picker import exists': "package:file_picker/file_picker.dart" in screen,
    'manual video pick method exists': '_pickVideoFromFileManager' in screen,
    'manual pick uses video file type': 'FileType.video' in screen,
    'manual pick returns path': 'Navigator.of(context).pop(path)' in screen,
    'manual pick button visible': '从文件管理选择视频' in screen,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} {name}")
if failed:
    raise SystemExit(f"Missing expected video picker fallback: {', '.join(failed)}")
