import 'package:face_swap_video/features/generation/providers/generation_provider.dart';
import 'package:face_swap_video/features/generation/services/api_service.dart';
import 'package:face_swap_video/features/generation/services/video_upload_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingApiService extends ApiService {
  String? capturedVideoTargetPath;

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<String> swapVideoJob({
    required String sourcePath,
    required String targetPath,
    UploadProgressCallback? onUploadProgress,
  }) async {
    capturedVideoTargetPath = targetPath;
    onUploadProgress?.call(100, 100);
    return 'job-optimized';
  }

  @override
  Future<String> pollSwapJob({
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1);
    return '/tmp/result.mp4';
  }
}

class _FakeVideoUploadOptimizer implements VideoUploadOptimizer {
  _FakeVideoUploadOptimizer(this.optimizedPath);

  final String optimizedPath;
  String? inputPath;
  bool cancelCalled = false;

  @override
  Future<String> optimizeForUpload(
    String targetPath, {
    VideoCompressionProgressCallback? onProgress,
  }) async {
    inputPath = targetPath;
    onProgress?.call(1);
    return optimizedPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
  }
}

class _LateUploadProgressApiService extends ApiService {
  UploadProgressCallback? _uploadProgress;

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<String> swapVideoJob({
    required String sourcePath,
    required String targetPath,
    UploadProgressCallback? onUploadProgress,
  }) async {
    _uploadProgress = onUploadProgress;
    onUploadProgress?.call(100, 100);
    return 'job-1';
  }

  @override
  Future<String> pollSwapJob({
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    _uploadProgress?.call(0, 100);
    onProgress?.call(0);
    return '/tmp/result.mp4';
  }
}

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

    test('requires exit confirmation when material is selected', () {
      final provider = GenerationProvider();

      expect(provider.shouldConfirmBeforeExit, isFalse);

      provider.setVideoPath('/tmp/source.mp4');

      expect(provider.shouldConfirmBeforeExit, isTrue);
    });

    test('requires exit confirmation while generation is processing', () {
      final provider = GenerationProvider()
        ..setVideoPath('/tmp/source.mp4')
        ..setFaceImagePath('/tmp/face.jpg')
        ..debugSetProcessingForTest();

      expect(provider.status, GenerationStatus.processing);
      expect(provider.shouldConfirmBeforeExit, isTrue);
    });

    test(
      'uses optimized video path for upload when optimizer returns one',
      () async {
        final api = _CapturingApiService();
        final optimizer = _FakeVideoUploadOptimizer('/tmp/optimized.mp4');
        final provider =
            GenerationProvider(api: api, videoUploadOptimizer: optimizer)
              ..setVideoPath('/tmp/source.mp4')
              ..setFaceImagePath('/tmp/face.jpg');

        await provider.startGeneration();

        expect(optimizer.inputPath, '/tmp/source.mp4');
        expect(api.capturedVideoTargetPath, '/tmp/optimized.mp4');
        expect(provider.status, GenerationStatus.completed);
      },
    );

    test(
      'keeps progress monotonic when a late upload callback arrives',
      () async {
        final provider =
            GenerationProvider(
                api: _LateUploadProgressApiService(),
                videoUploadOptimizer: const NoopVideoUploadOptimizer(),
              )
              ..setVideoPath('/tmp/source.mp4')
              ..setFaceImagePath('/tmp/face.jpg');

        final observedProgress = <double>[];
        provider.addListener(() => observedProgress.add(provider.progress));

        await provider.startGeneration();

        for (var i = 1; i < observedProgress.length; i++) {
          expect(
            observedProgress[i],
            greaterThanOrEqualTo(observedProgress[i - 1]),
            reason:
                'progress dropped from ${observedProgress[i - 1]} to ${observedProgress[i]}',
          );
        }
        expect(provider.status, GenerationStatus.completed);
        expect(provider.progress, 1.0);
      },
    );
  });
}
