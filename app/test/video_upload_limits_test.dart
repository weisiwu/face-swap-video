import 'package:face_swap_video/features/media/utils/video_upload_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateVideoUploadLimits', () {
    test('accepts videos up to 60 seconds and 100 MB', () {
      final result = validateVideoUploadLimits(
        duration: const Duration(seconds: 60),
        sizeBytes: maxVideoUploadBytes,
      );

      expect(result.isValid, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('rejects videos longer than 60 seconds', () {
      final result = validateVideoUploadLimits(
        duration: const Duration(seconds: 61),
        sizeBytes: 10 * 1024 * 1024,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('1分钟'));
    });

    test('rejects videos larger than 100 MB', () {
      final result = validateVideoUploadLimits(
        duration: const Duration(seconds: 30),
        sizeBytes: maxVideoUploadBytes + 1,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('100 MB'));
    });
  });
}
