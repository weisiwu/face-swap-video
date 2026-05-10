import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../utils/media_file_types.dart';

class ApiService {
  // Cloudflare Tunnel URL — auto-synced from server
  // The LaunchAgent writes this file; App reads it at startup
  static const String _defaultUrl = 'https://facefusion.baoganai.com';
  static const String _healthEndpoint = '/api/health';
  static const String _imageSwapEndpoint = '/api/swap/image';
  static const String _videoJobEndpoint = '/api/swap/video/job';
  static const String _videoStatusEndpointPrefix = '/api/swap/status';
  static const String _videoResultEndpointPrefix = '/api/swap/result';
  static const Duration _healthTimeout = Duration(seconds: 10);
  static const Duration _uploadTimeout = Duration(minutes: 5);
  static const Duration _downloadTimeout = Duration(minutes: 5);
  static const Duration _pollInterval = Duration(seconds: 4);
  static const Duration _pollTimeout = Duration(minutes: 35);
  static const Duration _statusRequestTimeout = Duration(seconds: 15);

  String _baseUrl;

  ApiService({String? baseUrl}) : _baseUrl = baseUrl ?? _defaultUrl;

  String get baseUrl => _baseUrl;

  /// Update the API base URL (e.g., when tunnel URL changes)
  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Health check
  Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl$_healthEndpoint'))
          .timeout(_healthTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Swap face in an image
  /// [sourcePath] - local path to the source face image
  /// [targetPath] - local path to the target image/video
  /// [onProgress] - callback (0.0 to 1.0) for upload progress
  /// Returns the downloaded file path of the result.
  Future<String> swapFace({
    required String sourcePath,
    required String targetPath,
    void Function(double progress)? onProgress,
  }) async {
    final isVideo = isVideoFilePath(targetPath);
    if (isVideo) {
      final jobId = await swapVideoJob(
        sourcePath: sourcePath,
        targetPath: targetPath,
      );
      return pollSwapJob(jobId: jobId, onProgress: onProgress);
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$_imageSwapEndpoint'),
    );

    request.files.add(await http.MultipartFile.fromPath('source', sourcePath));
    request.files.add(await http.MultipartFile.fromPath('target', targetPath));

    final streamedResponse = await request.send().timeout(_uploadTimeout);

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw ApiException(streamedResponse.statusCode, 'Swap failed: $body');
    }

    // Download result to temp file
    final ext = isVideo ? '.mp4' : '.jpg';
    final outputPath =
        '${Directory.systemTemp.path}/swapped_${DateTime.now().millisecondsSinceEpoch}$ext';

    final file = File(outputPath);
    final totalBytes =
        int.tryParse(streamedResponse.headers['content-length'] ?? '') ?? 0;

    var downloadedBytes = 0;
    final sink = file.openWrite();

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;
      if (totalBytes > 0 && onProgress != null) {
        onProgress(downloadedBytes / totalBytes);
      }
    }

    await sink.close();
    return outputPath;
  }

  Future<String> swapVideoJob({
    required String sourcePath,
    required String targetPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$_videoJobEndpoint'),
    );
    request.files.add(await http.MultipartFile.fromPath('source', sourcePath));
    request.files.add(await http.MultipartFile.fromPath('target', targetPath));

    final streamedResponse = await request.send().timeout(_uploadTimeout);
    final body = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode != 200) {
      throw ApiException(
        streamedResponse.statusCode,
        'Start video job failed: $body',
      );
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;
    final jobId = payload['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw ApiException(500, 'Server did not return a job id');
    }
    return jobId;
  }

  Future<String> pollSwapJob({
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    final startedAt = DateTime.now();

    var transientNetworkFailures = 0;

    while (DateTime.now().difference(startedAt) < _pollTimeout) {
      http.Response statusResponse;
      try {
        statusResponse = await http
            .get(Uri.parse('$_baseUrl$_videoStatusEndpointPrefix/$jobId'))
            .timeout(_statusRequestTimeout);
        transientNetworkFailures = 0;
      } catch (e) {
        if (_isTransientNetworkError(e) && transientNetworkFailures < 90) {
          transientNetworkFailures++;
          onProgress?.call(0.35);
          await Future<void>.delayed(_pollInterval);
          continue;
        }
        throw ApiException(0, '网络连接暂时不可用，请稍后重试');
      }
      if (statusResponse.statusCode != 200) {
        throw ApiException(
          statusResponse.statusCode,
          'Job status failed: ${statusResponse.body}',
        );
      }

      final payload = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      final status = payload['status'] as String?;
      if (status == 'completed') {
        onProgress?.call(0.95);
        return _downloadJobResult(jobId: jobId, onProgress: onProgress);
      }
      if (status == 'failed') {
        throw ApiException(
          500,
          payload['error']?.toString() ?? 'Video job failed',
        );
      }

      onProgress?.call(0.35);
      await Future<void>.delayed(_pollInterval);
    }

    throw ApiException(408, '视频处理超时，请稍后重试');
  }

  Future<String> _downloadJobResult({
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request(
      'GET',
      Uri.parse('$_baseUrl$_videoResultEndpointPrefix/$jobId'),
    );
    final streamedResponse = await request.send().timeout(_downloadTimeout);
    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw ApiException(
        streamedResponse.statusCode,
        'Download result failed: $body',
      );
    }

    final outputPath =
        '${Directory.systemTemp.path}/swapped_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final file = File(outputPath);
    final totalBytes =
        int.tryParse(streamedResponse.headers['content-length'] ?? '') ?? 0;
    var downloadedBytes = 0;
    final sink = file.openWrite();
    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(0.95 + (downloadedBytes / totalBytes) * 0.05);
      }
    }
    await sink.close();
    return outputPath;
  }

  bool _isTransientNetworkError(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException ||
        error.toString().contains('SocketException') ||
        error.toString().contains('Failed host lookup') ||
        error.toString().contains('failed host lookup');
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
