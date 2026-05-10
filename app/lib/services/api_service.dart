import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // Cloudflare Tunnel URL — auto-synced from server
  // The LaunchAgent writes this file; App reads it at startup
  static const String _defaultUrl =
      'https://mai-deck-commonly-falls.trycloudflare.com';

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
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 10));
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
    final isVideo = _isVideoFile(targetPath);
    final endpoint = isVideo ? '/api/swap/video' : '/api/swap/image';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$endpoint'),
    );

    request.files.add(await http.MultipartFile.fromPath('source', sourcePath));
    request.files.add(await http.MultipartFile.fromPath('target', targetPath));

    final streamedResponse =
        await request.send().timeout(const Duration(minutes: 5));

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw ApiException(
        streamedResponse.statusCode,
        'Swap failed: $body',
      );
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

  bool _isVideoFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4') ||
        ext.endsWith('.mov') ||
        ext.endsWith('.avi') ||
        ext.endsWith('.mkv');
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
