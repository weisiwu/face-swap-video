import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:face_swap_video/core/services/app_logger.dart';
import 'package:face_swap_video/features/generation/utils/job_progress.dart';
import 'package:face_swap_video/features/media/utils/media_file_types.dart';

const String _logTag = 'ApiService';

typedef UploadProgressCallback = void Function(int sentBytes, int totalBytes);
typedef SwapJobStatusCallback = void Function(SwapJobStatus status);

class SwapJobStatus {
  const SwapJobStatus({
    required this.progress,
    required this.status,
    this.stage,
    this.stageLabel,
  });

  final double progress;
  final String? status;
  final String? stage;
  final String? stageLabel;

  String get displayLabel {
    final label = stageLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    switch (stage) {
      case 'preprocessing':
        return '预处理视频';
      case 'detecting_face':
        return '检测人脸';
      case 'swapping_frame':
        return '逐帧换脸';
      case 'encoding':
        return '编码输出';
      case 'queued':
        return '排队中';
    }
    return '逐帧换脸';
  }
}

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
    appLogger.i(_logTag, 'baseUrl updated to $_baseUrl');
  }

  /// Health check
  Future<bool> healthCheck() async {
    final url = '$_baseUrl$_healthEndpoint';
    appLogger.i(_logTag, 'healthCheck -> GET $url');
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.get(Uri.parse(url)).timeout(_healthTimeout);
      stopwatch.stop();
      final ok = response.statusCode == 200;
      appLogger.i(
        _logTag,
        'healthCheck status=${response.statusCode} ok=$ok elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return ok;
    } catch (error, stack) {
      stopwatch.stop();
      appLogger.w(
        _logTag,
        'healthCheck failed elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stack,
      );
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
    appLogger.i(
      _logTag,
      'swapFace start isVideo=$isVideo sourcePath=$sourcePath targetPath=$targetPath',
    );
    if (isVideo) {
      final jobId = await swapVideoJob(
        sourcePath: sourcePath,
        targetPath: targetPath,
        onUploadProgress: onUploadProgress,
      );
      return pollSwapJob(jobId: jobId, onProgress: onProgress);
    }
    final url = '$_baseUrl$_imageSwapEndpoint';
    final sourceSize = await _safeFileSize(sourcePath);
    final targetSize = await _safeFileSize(targetPath);
    appLogger.i(
      _logTag,
      'swapFace image -> POST $url sourceBytes=$sourceSize targetBytes=$targetSize',
    );
    final stopwatch = Stopwatch()..start();
    final request = http.MultipartRequest('POST', Uri.parse(url));

    request.files.add(await http.MultipartFile.fromPath('source', sourcePath));
    request.files.add(await http.MultipartFile.fromPath('target', targetPath));

    final streamedResponse = await _sendMultipartRequest(
      request,
      onUploadProgress: onUploadProgress,
    ).timeout(_uploadTimeout);

    if (streamedResponse.statusCode != 200) {
      await streamedResponse.stream.drain<void>();
      stopwatch.stop();
      appLogger.e(
        _logTag,
        'swapFace image non-200 status=${streamedResponse.statusCode} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      throw ApiException(streamedResponse.statusCode, '处理接口返回异常，请稍后重试');
    }

    // Download result to temp file
    final ext = isVideo ? '.mp4' : '.jpg';
    final outputPath =
        '${Directory.systemTemp.path}/swapped_${DateTime.now().millisecondsSinceEpoch}$ext';

    final file = File(outputPath);
    final totalBytes =
        int.tryParse(streamedResponse.headers['content-length'] ?? '') ?? 0;
    appLogger.i(
      _logTag,
      'swapFace image download outputPath=$outputPath totalBytes=$totalBytes',
    );

    var downloadedBytes = 0;
    final sink = file.openWrite();

    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(downloadedBytes / totalBytes);
        }
      }
    } catch (error, stack) {
      stopwatch.stop();
      appLogger.e(
        _logTag,
        'swapFace image download stream error downloadedBytes=$downloadedBytes elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stack,
      );
      await sink.close();
      rethrow;
    }

    await sink.close();
    stopwatch.stop();
    appLogger.i(
      _logTag,
      'swapFace image done downloadedBytes=$downloadedBytes elapsedMs=${stopwatch.elapsedMilliseconds} outputPath=$outputPath',
    );
    return outputPath;
  }

  Future<String> swapVideoJob({
    required String sourcePath,
    required String targetPath,
    UploadProgressCallback? onUploadProgress,
  }) async {
    final url = '$_baseUrl$_videoJobEndpoint';
    final sourceSize = await _safeFileSize(sourcePath);
    final targetSize = await _safeFileSize(targetPath);
    appLogger.i(
      _logTag,
      'swapVideoJob -> POST $url sourceBytes=$sourceSize targetBytes=$targetSize sourcePath=$sourcePath targetPath=$targetPath',
    );

    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.files.add(await http.MultipartFile.fromPath('source', sourcePath));
    request.files.add(await http.MultipartFile.fromPath('target', targetPath));

    final stopwatch = Stopwatch()..start();
    try {
      final streamedResponse = await _sendMultipartRequest(
        request,
        onUploadProgress: onUploadProgress,
      ).timeout(_uploadTimeout);
      final body = await streamedResponse.stream.bytesToString();
      stopwatch.stop();
      appLogger.i(
        _logTag,
        'swapVideoJob response status=${streamedResponse.statusCode} elapsedMs=${stopwatch.elapsedMilliseconds} bodyBytes=${body.length}',
      );
      if (streamedResponse.statusCode != 200) {
        appLogger.w(_logTag, 'swapVideoJob non-200 body=${_truncate(body)}');
        throw ApiException(streamedResponse.statusCode, '处理接口返回异常，请稍后重试');
      }

      final payload = jsonDecode(body) as Map<String, dynamic>;
      final jobId = payload['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        appLogger.e(
          _logTag,
          'swapVideoJob missing job_id payload=${_truncate(body)}',
        );
        throw ApiException(500, 'Server did not return a job id');
      }
      appLogger.i(_logTag, 'swapVideoJob jobId=$jobId');
      return jobId;
    } on ApiException {
      rethrow;
    } catch (error, stack) {
      stopwatch.stop();
      appLogger.e(
        _logTag,
        'swapVideoJob failure elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stack,
      );
      rethrow;
    }
  }

  Future<String> pollSwapJob({
    required String jobId,
    void Function(double progress)? onProgress,
    SwapJobStatusCallback? onStatus,
  }) async {
    final startedAt = DateTime.now();
    appLogger.i(_logTag, 'pollSwapJob start jobId=$jobId');

    var transientNetworkFailures = 0;
    var pollCount = 0;

    while (DateTime.now().difference(startedAt) < _pollTimeout) {
      http.Response statusResponse;
      try {
        statusResponse = await http
            .get(Uri.parse('$_baseUrl$_videoStatusEndpointPrefix/$jobId'))
            .timeout(_statusRequestTimeout);
        transientNetworkFailures = 0;
      } catch (e, stack) {
        if (_isTransientNetworkError(e) && transientNetworkFailures < 90) {
          transientNetworkFailures++;
          pollCount++;
          appLogger.w(
            _logTag,
            'pollSwapJob transient network error jobId=$jobId pollCount=$pollCount transientCount=$transientNetworkFailures',
            e,
          );
          final fallbackProgress = resolveJobProgress(const {
            'status': 'processing',
          }, pollCount: pollCount);
          onProgress?.call(fallbackProgress);
          onStatus?.call(
            SwapJobStatus(
              progress: fallbackProgress,
              status: 'processing',
              stage: 'swapping_frame',
              stageLabel: '逐帧换脸',
            ),
          );
          await Future<void>.delayed(_pollInterval);
          continue;
        }
        appLogger.e(
          _logTag,
          'pollSwapJob fatal network error jobId=$jobId pollCount=$pollCount',
          e,
          stack,
        );
        throw ApiException(0, '网络连接暂时不可用，请稍后重试');
      }
      if (statusResponse.statusCode != 200) {
        appLogger.w(
          _logTag,
          'pollSwapJob non-200 jobId=$jobId status=${statusResponse.statusCode} body=${_truncate(statusResponse.body)}',
        );
        throw ApiException(statusResponse.statusCode, '处理接口返回异常，请稍后重试');
      }

      final payload = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      pollCount++;
      final status = payload['status'] as String?;
      final serverProgress = payload['progress'];
      final stage = payload['stage'] as String?;
      final stageLabel = payload['stage_label'] as String?;
      final resolvedProgress = resolveJobProgress(
        payload,
        pollCount: pollCount,
      );
      final elapsedSec = DateTime.now().difference(startedAt).inSeconds;
      appLogger.i(
        _logTag,
        'pollSwapJob jobId=$jobId pollCount=$pollCount elapsedSec=$elapsedSec status=$status stage=$stage serverProgress=$serverProgress resolvedProgress=${resolvedProgress.toStringAsFixed(3)}',
      );
      final jobStatus = SwapJobStatus(
        progress: resolvedProgress,
        status: status,
        stage: stage,
        stageLabel: stageLabel,
      );
      if (status == 'completed') {
        onProgress?.call(resolvedProgress);
        onStatus?.call(jobStatus);
        return _downloadJobResult(jobId: jobId, onProgress: onProgress);
      }
      if (status == 'failed' || status == 'cancelled') {
        appLogger.e(
          _logTag,
          'pollSwapJob terminal jobId=$jobId status=$status error=${payload['error']}',
        );
        throw ApiException(500, _userFriendlyProcessingError(payload['error']));
      }

      onProgress?.call(resolvedProgress);
      onStatus?.call(jobStatus);
      await Future<void>.delayed(_pollInterval);
    }

    appLogger.e(
      _logTag,
      'pollSwapJob timeout jobId=$jobId pollCount=$pollCount totalSec=${DateTime.now().difference(startedAt).inSeconds}',
    );
    throw ApiException(408, '视频处理超时，请稍后重试');
  }

  Future<void> cancelSwapJob(String jobId) async {
    appLogger.i(_logTag, 'cancelSwapJob jobId=$jobId');
    try {
      final response = await http
          .post(Uri.parse('$_baseUrl$_videoCancelEndpointPrefix/$jobId'))
          .timeout(_statusRequestTimeout);
      appLogger.i(
        _logTag,
        'cancelSwapJob jobId=$jobId status=${response.statusCode}',
      );
    } catch (error, stack) {
      // Best-effort: local cancellation must not block the UI.
      appLogger.w(_logTag, 'cancelSwapJob failed jobId=$jobId', error, stack);
    }
  }

  Future<String> _downloadJobResult({
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    final url = '$_baseUrl$_videoResultEndpointPrefix/$jobId';
    appLogger.i(_logTag, 'downloadJobResult start jobId=$jobId url=$url');
    final stopwatch = Stopwatch()..start();
    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await request.send().timeout(_downloadTimeout);
    if (streamedResponse.statusCode != 200) {
      await streamedResponse.stream.drain<void>();
      stopwatch.stop();
      appLogger.e(
        _logTag,
        'downloadJobResult non-200 jobId=$jobId status=${streamedResponse.statusCode}',
      );
      throw ApiException(streamedResponse.statusCode, '处理接口返回异常，请稍后重试');
    }

    final outputPath =
        '${Directory.systemTemp.path}/swapped_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final file = File(outputPath);
    final totalBytes =
        int.tryParse(streamedResponse.headers['content-length'] ?? '') ?? 0;
    appLogger.i(
      _logTag,
      'downloadJobResult writing jobId=$jobId outputPath=$outputPath totalBytes=$totalBytes',
    );
    var downloadedBytes = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(0.95 + (downloadedBytes / totalBytes) * 0.05);
        }
      }
    } catch (error, stack) {
      stopwatch.stop();
      appLogger.e(
        _logTag,
        'downloadJobResult stream error jobId=$jobId downloadedBytes=$downloadedBytes',
        error,
        stack,
      );
      await sink.close();
      rethrow;
    }
    await sink.close();
    stopwatch.stop();
    appLogger.i(
      _logTag,
      'downloadJobResult done jobId=$jobId downloadedBytes=$downloadedBytes elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return outputPath;
  }

  Future<int> _safeFileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return -1;
    }
  }

  String _truncate(String value, {int max = 500}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...<truncated>';
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
    var nextLogThreshold = 0.25;
    final stopwatch = Stopwatch()..start();
    appLogger.i(_logTag, 'upload start totalBytes=$totalBytes');
    onUploadProgress?.call(sentBytes, totalBytes);
    try {
      await for (final chunk in stream) {
        sentBytes += chunk.length;
        onUploadProgress?.call(sentBytes, totalBytes);
        if (totalBytes > 0) {
          final fraction = sentBytes / totalBytes;
          while (nextLogThreshold <= 1.0 && fraction >= nextLogThreshold) {
            appLogger.i(
              _logTag,
              'upload progress ${(nextLogThreshold * 100).round()}% sentBytes=$sentBytes totalBytes=$totalBytes elapsedMs=${stopwatch.elapsedMilliseconds}',
            );
            nextLogThreshold += 0.25;
          }
        }
        yield chunk;
      }
      stopwatch.stop();
      appLogger.i(
        _logTag,
        'upload finished sentBytes=$sentBytes totalBytes=$totalBytes elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error, stack) {
      stopwatch.stop();
      appLogger.e(
        _logTag,
        'upload aborted sentBytes=$sentBytes totalBytes=$totalBytes elapsedMs=${stopwatch.elapsedMilliseconds}',
        error,
        stack,
      );
      rethrow;
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
