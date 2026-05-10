import 'package:face_swap_video/providers/generation_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GenerationProvider input state', () {
    test('moves from idle to ready only after both inputs are selected', () {
      final provider = GenerationProvider();

      expect(provider.status, GenerationStatus.idle);
      expect(provider.canSubmit, isFalse);
      expect(provider.videoFileName, '未选择');
      expect(provider.faceImageFileName, '未选择');

      provider.setVideoPath('/tmp/source.mp4');
      expect(provider.status, GenerationStatus.idle);
      expect(provider.canSubmit, isFalse);
      expect(provider.videoFileName, 'source.mp4');

      provider.setFaceImagePath('/tmp/face.jpg');
      expect(provider.status, GenerationStatus.ready);
      expect(provider.canSubmit, isTrue);
      expect(provider.faceImageFileName, 'face.jpg');
    });

    test('reset clears selected inputs and returns to idle', () {
      final provider = GenerationProvider()
        ..setVideoPath('/tmp/source.mp4')
        ..setFaceImagePath('/tmp/face.jpg');

      provider.reset();

      expect(provider.status, GenerationStatus.idle);
      expect(provider.canSubmit, isFalse);
      expect(provider.videoPath, isNull);
      expect(provider.faceImagePath, isNull);
      expect(provider.progress, 0.0);
    });
  });
}
