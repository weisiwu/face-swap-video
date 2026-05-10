#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
generation = (root / 'lib/screens/generation_screen.dart').read_text()
photo_grid = (root / 'lib/screens/photo_grid_screen.dart').read_text()
pubspec = (root / 'pubspec.yaml').read_text()

checks = [
    ('photo file picker import', "import 'package:file_picker/file_picker.dart';" in photo_grid),
    ('photo file manager method', '_pickPhotoFromFileManager' in photo_grid and 'FileType.image' in photo_grid),
    ('photo file manager visible button', '从文件管理选择照片' in photo_grid),
    ('photo file manager button in layout', '_buildFileManagerButton()' in photo_grid),
    ('auto completion dialog listener', 'provider.status == GenerationStatus.completed' in generation and '_showCompletionDialog(provider);' in generation),
    ('video_player dependency', 'video_player:' in pubspec),
    ('video_player import', "import 'package:video_player/video_player.dart';" in generation),
    ('playable preview widget', 'class _ResultVideoPreview' in generation and 'VideoPlayerController.file' in generation),
    ('preview toggles playback on tap', '_togglePlayback' in generation and '_controller.play()' in generation and '_controller.pause()' in generation),
    ('completion dialog contains preview', '_ResultVideoPreview(resultPath: resultPath)' in generation),
    ('preview dialog compact size', 'maxWidth: 400' in generation and 'EdgeInsets.symmetric(horizontal: 36)' in generation),
    ('preview remains landscape', 'aspectRatio: 16 / 9' in generation[generation.index('class _ResultVideoPreview'):]),
    ('preview uses video progress bar', 'VideoProgressIndicator' in generation and 'allowScrubbing: true' in generation and 'VideoProgressColors' in generation),
    ('completed page opens preview instead of direct save', 'label: \'预览并保存\'' in generation and '_showCompletionDialog(provider)' in generation),
    ('result button full width', 'width: double.infinity' in generation[generation.index('Widget _buildResultButton'):]),
    ('bottom save button text', "label: Text(_savingResult ? '保存中...' : '保存到相册')" in generation),
    ('main preview button normal size', 'height: 44' in generation[generation.index('Widget _buildResultButton'):] and 'fontSize: 14' in generation[generation.index('Widget _buildResultButton'):]),
    ('dialog save button normal size', 'height: 40' in generation[generation.index('Future<void> _showCompletionDialog'):] and 'fontSize: 14' in generation[generation.index('Future<void> _showCompletionDialog'):generation.index('Future<void> _saveResultVideo')]),
    ('play overlay button compact', 'width: 26' in generation[generation.index('class _ResultVideoPreview'):] and 'height: 26' in generation[generation.index('class _ResultVideoPreview'):] and 'size: 22' in generation[generation.index('class _ResultVideoPreview'):] and 'width: 34' not in generation[generation.index('class _ResultVideoPreview'):]),
    ('preview plays once only', 'await _controller.setLooping(false);' in generation and '_handlePreviewCompleted' in generation and '_controller.pause();' in generation[generation.index('void _handlePreviewCompleted'):]),
]

failed = [name for name, ok in checks if not ok]
if failed:
    print('FAILED checks:')
    for name in failed:
        print(f'- {name}')
    raise SystemExit(1)
print('All result preview UI checks passed.')
