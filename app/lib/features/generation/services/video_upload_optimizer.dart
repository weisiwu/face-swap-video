import 'dart:async';
import 'dart:io';

import 'package:video_compress/video_compress.dart';

import 'package:face_swap_video/features/media/utils/media_file_types.dart';

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
    if (!isVideoFilePath(targetPath)) return targetPath;

    final sourceFile = File(targetPath);
    if (!await sourceFile.exists()) return targetPath;

    final originalBytes = await sourceFile.length();
    if (originalBytes < _minCompressBytes) return targetPath;

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
      if (optimizedPath == null || optimizedPath.isEmpty) return targetPath;

      final optimizedFile = File(optimizedPath);
      if (!await optimizedFile.exists()) return targetPath;

      final optimizedBytes = await optimizedFile.length();
      if (optimizedBytes <= 0 || optimizedBytes >= originalBytes) {
        return targetPath;
      }

      return optimizedPath;
    } catch (_) {
      return targetPath;
    } finally {
      subscription?.unsubscribe();
    }
  }

  @override
  Future<void> cancel() => VideoCompress.cancelCompression();
}
