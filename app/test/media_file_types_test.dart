import 'package:flutter_test/flutter_test.dart';
import 'package:face_swap_video/features/media/utils/media_file_types.dart';

void main() {
  group('isVideoFilePath', () {
    test('matches supported video extensions case-insensitively', () {
      expect(isVideoFilePath('/tmp/source.mp4'), isTrue);
      expect(isVideoFilePath('/tmp/source.MOV'), isTrue);
      expect(isVideoFilePath('/tmp/source.Avi'), isTrue);
      expect(isVideoFilePath('/tmp/source.mkv'), isTrue);
    });

    test('does not match non-video extensions', () {
      expect(isVideoFilePath('/tmp/source.jpg'), isFalse);
      expect(isVideoFilePath('/tmp/source.png'), isFalse);
      expect(isVideoFilePath('/tmp/source.mp4.jpg'), isFalse);
    });
  });
}
