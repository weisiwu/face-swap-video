import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:face_swap_video/features/generation/utils/job_progress.dart';
import 'package:face_swap_video/features/media/utils/media_file_types.dart';

typedef UploadProgressCallback = void Function(int sentBytes, int totalBytes);

class ApiService {
  // Cloudflare Tunnel URL — auto-synced from server
  // The LaunchAgent writes this file; App reads it at startup
  static const String _defaultUrl = 'https://facefusion.baoganai.com';
  static const String _healthEndpoint = '/api/health';
  static const String _imageSwapEndpoint = '/api/swap/image';
  static const String _videoJobEndpoint = '/api/swap/video/job';
  static const String _videoStatusEndpointPrefix = '/api/swap/status';
  static const String _videoCancelEndpointPrefix = '/api/swap/cancel';
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
  /// [onProgress] - callback (0.0 to 1.0) for result download progress.
  /// [onUploadProgress] - callback with uploaded bytes and multipart payload size.
  /// Returns the downloaded file path of the result.
  Future<String> swapFace({
    required String sourcePath,
    required String targetPath,
    void Function(double progress)? onProgress,
    UploadProgressCallback? onUploadProgress,
  }) async {
    final isVideo = isVideoFilePath(targetPath);
    if (isVideo) {
      final jobId = await swapVideoJob(
        sourcePath: sourcePath,
        targetPath: targetPath,
        onUploadProgress: onUploadProgress,
      );
      return pollSwapJob(jobId: jobId, onProgress: onProgress);
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$_imageSwapEndpoint'),
    );

    request.files.add(await http.MultipartFile.fromPath('source', sourcePath));
    request.files.add(await http.MultipartFile.fromPath('target', targetPath));

    final streamedResponse = await _sendMultipartRequest(
      request,
      onUploadProgress: onUploadProgress,
    ).timeout(_uploadTimeout);

    if (streamedResponse.statusCode != 200) {
      await streamedResponse.stream.drain<void>();
      throw ApiException(streamedResponse.statusCode, '处理接口返回异常，请稍后重试');
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
    UploadProgressCallback? onUploadProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$_videoJobEndpoint'),
    );
    request.files.add(await http.MultipartFile.fromPath('source', sourcePath));
    request.files.add(await http.MultipartFile.fromPath('target', targetPath));

    final streamedResponse = await _sendMultipartRequest(
      request,
      onUploadProgress: onUploadProgress,
    ).timeout(_uploadTimeout);
    final body = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode != 200) {
      throw ApiException(streamedResponse.statusCode, '处理接口返回异常，请稍后重试');
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
    var pollCount = 0;

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
          pollCount++;
          onProgress?.call(
            resolveJobProgress(const {
              'status': 'processing',
            }, pollCount: pollCount),
          );
          await Future<void>.delayed(_pollInterval);
          continue;
        }
        throw ApiException(0, '网络连接暂时不可用，请稍后重试');
      }
      if (statusResponse.statusCode != 200) {
        throw ApiException(statusResponse.statusCode, '处理接口返回异常，请稍后重试');
      }

      final payload = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      pollCount++;
      final status = payload['status'] as String?;
      final resolvedProgress = resolveJobProgress(
        payload,
        pollCount: pollCount,
      );
      if (status == 'completed') {
        onProgress?.call(resolvedProgress);
        return _downloadJobResult(jobId: jobId, onProgress: onProgress);
      }
      if (status == 'failed' || status == 'cancelled') {
        throw ApiException(500, _userFriendlyProcessingError(payload['error']));
      }

      onProgress?.call(resolvedProgress);
      await Future<void>.delayed(_pollInterval);
    }

    throw ApiException(408, '视频处理超时，请稍后重试');
  }

  Future<void> cancelSwapJob(String jobId) async {
    try {
      await http
          .post(Uri.parse('$_baseUrl$_videoCancelEndpointPrefix/$jobId'))
          .timeout(_statusRequestTimeout);
    } catch (_) {
      // Best-effort: local cancellation must not block the UI.
    }
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
      await streamedResponse.stream.drain<void>();
      throw ApiException(streamedResponse.statusCode, '处理接口返回异常，请稍后重试');
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

  Future<http.StreamedResponse> _sendMultipartRequest(
    http.MultipartRequest request, {
    UploadProgressCallback? onUploadProgress,
  }) async {
    final client = http.Client();
    final totalBytes = request.contentLength;
    final byteStream = request.finalize();
    final streamedRequest = http.StreamedRequest(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..contentLength = totalBytes;

    unawaited(
      streamedRequest.sink
          .addStream(
            _trackUploadProgress(
              byteStream,
              totalBytes: totalBytes,
              onUploadProgress: onUploadProgress,
            ),
          )
          .then((_) => streamedRequest.sink.close())
          .catchError((Object error, StackTrace stackTrace) {
            streamedRequest.sink.addError(error, stackTrace);
          }),
    );

    try {
      final response = await client.send(streamedRequest);
      return _closeClientWhenDone(response, client);
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  Stream<List<int>> _trackUploadProgress(
    http.ByteStream stream, {
    required int totalBytes,
    UploadProgressCallback? onUploadProgress,
  }) async* {
    var sentBytes = 0;
    onUploadProgress?.call(sentBytes, totalBytes);
    await for (final chunk in stream) {
      sentBytes += chunk.length;
      onUploadProgress?.call(sentBytes, totalBytes);
      yield chunk;
    }
  }

  http.StreamedResponse _closeClientWhenDone(
    http.StreamedResponse response,
    http.Client client,
  ) {
    final closingStream = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) => sink.add(chunk),
        handleError: (error, stackTrace, sink) {
          client.close();
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          client.close();
          sink.close();
        },
      ),
    );

    return http.StreamedResponse(
      closingStream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  bool _isTransientNetworkError(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException ||
        error.toString().contains('SocketException') ||
        error.toString().contains('Failed host lookup') ||
        error.toString().contains('failed host lookup');
  }

  String _userFriendlyProcessingError(Object? rawError) {
    final message = rawError?.toString().trim() ?? '';
    if (message.isEmpty) {
      return '处理接口返回异常，请稍后重试';
    }

    final normalized = message.toLowerCase();
    if (normalized.contains('no source face detected') ||
        normalized.contains('source face')) {
      return '没有检测到人脸，请换一张清晰正脸照后重试';
    }
    if (normalized.contains('no target face detected') ||
        normalized.contains('target face')) {
      return '目标视频中没有检测到可替换的人脸，请换一段正脸更清晰的视频';
    }

    return message;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
