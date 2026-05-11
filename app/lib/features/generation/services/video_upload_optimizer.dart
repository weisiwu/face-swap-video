import 'dart:async';
import 'dart:io';

import 'package:video_compress/video_compress.dart';

import 'package:face_swap_video/core/services/app_logger.dart';
import 'package:face_swap_video/features/media/utils/media_file_types.dart';

const String _logTag = 'VideoUploadOptimizer';

typedef VideoCompressionProgressCallback = void Function(double progress);

abstract class VideoUploadOptimizer {
  Future<String> optimizeForUpload(
    String targetPath, {
    VideoCompressionProgressCallback? onProgress,
  });

  Future<void> cancel();
}

class NoopVideoUploadOptimizer implements VideoUploadOptimizer {
  const NoopVideoUploadOptimizer();

  @override
  Future<String> optimizeForUpload(
    String targetPath, {
    VideoCompressionProgressCallback? onProgress,
  }) async {
    return targetPath;
  }

  @override
  Future<void> cancel() async {}
}

class VideoCompressUploadOptimizer implements VideoUploadOptimizer {
  static const int _minCompressBytes = 5 * 1024 * 1024;

  @override
  Future<String> optimizeForUpload(
    String targetPath, {
    VideoCompressionProgressCallback? onProgress,
  }) async {
    if (!isVideoFilePath(targetPath)) {
      appLogger.i(_logTag, 'skip non-video path=$targetPath');
      return targetPath;
    }

    final sourceFile = File(targetPath);
    if (!await sourceFile.exists()) {
      appLogger.w(_logTag, 'source missing path=$targetPath');
      return targetPath;
    }

    final originalBytes = await sourceFile.length();
    if (originalBytes < _minCompressBytes) {
      appLogger.i(
        _logTag,
        'skip small video originalBytes=$originalBytes threshold=$_minCompressBytes path=$targetPath',
      );
      return targetPath;
    }

    appLogger.i(
      _logTag,
      'compress start originalBytes=$originalBytes path=$targetPath',
    );
    final stopwatch = Stopwatch()..start();
    Subscription? subscription;
    try {
      subscription = VideoCompress.compressProgress$.subscribe((progress) {
        onProgress?.call((progress / 100).clamp(0.0, 1.0).toDouble());
      });

      final mediaInfo = await VideoCompress.compressVideo(
        targetPath,
        quality: VideoQuality.Res960x540Quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 24,
      );
      final optimizedPath = mediaInfo?.path;
      if (optimizedPath == null || optimizedPath.isEmpty) {
        appLogger.w(
          _logTag,
          'compress returned empty path; falling back to original',
        );
        return targetPath;
      }

      final optimizedFile = File(optimizedPath);
      if (!await optimizedFile.exists()) {
        appLogger.w(_logTag, 'compress output missing path=$optimizedPath');
        return targetPath;
      }

      final optimizedBytes = await optimizedFile.length();
      stopwatch.stop();
      if (optimizedBytes <= 0 || optimizedBytes >= originalBytes) {
        appLogger.i(
          _logTag,
          'compress not beneficial originalBytes=$originalBytes optimizedBytes=$optimizedBytes elapsedMs=${stopwatch.elapsedMilliseconds}; using original',
        );
        return targetPath;
      }

      appLogger.i(
        _logTag,
        'compress done originalBytes=$originalBytes optimizedBytes=$optimizedBytes elapsedMs=${stopwatch.elapsedMilliseconds} path=$optimizedPath',
      );
      return optimizedPath;
    } catch (error, stack) {
      stopwatch.stop();
      appLogger.w(
        _logTag,
        'compress error elapsedMs=${stopwatch.elapsedMilliseconds}; falling back to original',
        error,
        stack,
      );
      return targetPath;
    } finally {
      subscription?.unsubscribe();
    }
  }

  @override
  Future<void> cancel() {
    appLogger.i(_logTag, 'cancel compression requested');
    return VideoCompress.cancelCompression();
  }
}
