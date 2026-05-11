import 'package:face_swap_video/features/generation/utils/transfer_progress_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatTransferBytes', () {
    test('formats bytes below one megabyte as rounded KB', () {
      expect(formatTransferBytes(512), '1 KB');
      expect(formatTransferBytes(1536), '2 KB');
    });

    test('formats megabytes with one decimal place when needed', () {
      expect(formatTransferBytes(10 * 1024 * 1024), '10 MB');
      expect(formatTransferBytes(10 * 1024 * 1024 + 512 * 1024), '10.5 MB');
    });
  });

  group('formatUploadProgressLabel', () {
    test('shows uploaded and total bytes in parentheses', () {
      expect(
        formatUploadProgressLabel(
          uploadedBytes: 512 * 1024,
          totalBytes: 10 * 1024 * 1024,
        ),
        '上传素材中...（512 KB / 10 MB）',
      );
    });

    test('falls back to the base label when total bytes is unknown', () {
      expect(
        formatUploadProgressLabel(uploadedBytes: 512 * 1024, totalBytes: 0),
        '上传素材中...',
      );
    });
  });
}
