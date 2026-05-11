import 'dart:async';

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
    onProgress?.call(0.5);
    return '/tmp/result.mp4';
  }
}

class _StagedProgressApiService extends ApiService {
  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<String> swapVideoJob({
    required String sourcePath,
    required String targetPath,
    UploadProgressCallback? onUploadProgress,
  }) async {
    onUploadProgress?.call(0, 100);
    onUploadProgress?.call(50, 100);
    onUploadProgress?.call(100, 100);
    return 'job-staged';
  }

  @override
  Future<String> pollSwapJob({
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.25);
    onProgress?.call(1);
    return '/tmp/result.mp4';
  }
}

class _TimeoutApiService extends ApiService {
  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<String> swapVideoJob({
    required String sourcePath,
    required String targetPath,
    UploadProgressCallback? onUploadProgress,
  }) async {
    onUploadProgress?.call(100, 100);
    return 'job-timeout';
  }

  @override
  Future<String> pollSwapJob({
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    throw TimeoutException('status timeout');
  }
}

class _CancelableApiService extends ApiService {
  final Completer<String> _pollCompleter = Completer<String>();
  String? cancelledJobId;

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<String> swapVideoJob({
    required String sourcePath,
    required String targetPath,
    UploadProgressCallback? onUploadProgress,
  }) async {
    onUploadProgress?.call(100, 100);
    return 'job-cancel-me';
  }

  @override
  Future<String> pollSwapJob({
    required String jobId,
    void Function(double progress)? onProgress,
  }) => _pollCompleter.future;

  @override
  Future<void> cancelSwapJob(String jobId) async {
    cancelledJobId = jobId;
    if (!_pollCompleter.isCompleted) {
      _pollCompleter.completeError(ApiException(499, 'cancelled'));
    }
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

        final observedProcessingProgress = <double>[];
        provider.addListener(() {
          if (provider.currentStep?.contains('服务器处理') ?? false) {
            observedProcessingProgress.add(provider.progress);
          }
        });

        await provider.startGeneration();

        expect(observedProcessingProgress, isNotEmpty);
        for (var i = 1; i < observedProcessingProgress.length; i++) {
          expect(
            observedProcessingProgress[i],
            greaterThanOrEqualTo(observedProcessingProgress[i - 1]),
            reason:
                'processing progress dropped from ${observedProcessingProgress[i - 1]} to ${observedProcessingProgress[i]}',
          );
        }
        expect(provider.status, GenerationStatus.completed);
        expect(provider.progress, 1.0);
      },
    );

    test(
      'resets progress when moving from upload stage to processing stage',
      () async {
        final provider =
            GenerationProvider(
                api: _StagedProgressApiService(),
                videoUploadOptimizer: const NoopVideoUploadOptimizer(),
              )
              ..setVideoPath('/tmp/source.mp4')
              ..setFaceImagePath('/tmp/face.jpg');

        final observations = <String>[];
        provider.addListener(() {
          observations.add('${provider.currentStep}|${provider.progress}');
        });

        await provider.startGeneration();

        expect(
          observations,
          contains(
            predicate<String>(
              (entry) => entry.contains('上传素材中') && entry.endsWith('|0.0'),
            ),
          ),
        );
        expect(
          observations,
          contains(
            predicate<String>(
              (entry) => entry.contains('上传素材中') && entry.endsWith('|1.0'),
            ),
          ),
        );
        expect(
          observations,
          contains(
            predicate<String>(
              (entry) => entry.contains('服务器处理中') && entry.endsWith('|0.0'),
            ),
          ),
        );
        expect(
          observations,
          contains(
            predicate<String>(
              (entry) => entry.contains('服务器处理中') && entry.endsWith('|0.25'),
            ),
          ),
        );
        expect(provider.status, GenerationStatus.completed);
      },
    );

    test('shows a clear timeout message when processing times out', () async {
      final provider =
          GenerationProvider(
              api: _TimeoutApiService(),
              videoUploadOptimizer: const NoopVideoUploadOptimizer(),
            )
            ..setVideoPath('/tmp/source.mp4')
            ..setFaceImagePath('/tmp/face.jpg');

      await provider.startGeneration();

      expect(provider.status, GenerationStatus.failed);
      expect(provider.errorMessage, '处理超时，请稍后重试');
      expect(provider.currentStep, '处理失败');
    });

    test('cancels server video job when user cancels generation', () async {
      final api = _CancelableApiService();
      final optimizer = _FakeVideoUploadOptimizer('/tmp/optimized.mp4');
      final provider =
          GenerationProvider(api: api, videoUploadOptimizer: optimizer)
            ..setVideoPath('/tmp/source.mp4')
            ..setFaceImagePath('/tmp/face.jpg');

      final generation = provider.startGeneration();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      provider.cancelGeneration();
      await generation;

      expect(api.cancelledJobId, 'job-cancel-me');
      expect(optimizer.cancelCalled, isTrue);
      expect(provider.status, GenerationStatus.ready);
    });
  });
}
