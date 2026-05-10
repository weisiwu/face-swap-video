import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

enum GenerationStatus { idle, ready, processing, completed, failed }

class GenerationProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  String? _videoPath;
  String? _faceImagePath;
  GenerationStatus _status = GenerationStatus.idle;
  double _progress = 0.0;
  String? _errorMessage;
  String? _resultVideoPath;
  String? _currentStep;

  // Getters
  String? get videoPath => _videoPath;
  String? get faceImagePath => _faceImagePath;
  GenerationStatus get status => _status;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get resultVideoPath => _resultVideoPath;
  String? get currentStep => _currentStep;

  bool get canSubmit =>
      _videoPath != null &&
      _faceImagePath != null &&
      _status != GenerationStatus.processing;

  String get videoFileName =>
      _videoPath?.split('/').last ?? '未选择';
  String get faceImageFileName =>
      _faceImagePath?.split('/').last ?? '未选择';

  void setVideoPath(String path) {
    _videoPath = path;
    _updateReadyStatus();
    notifyListeners();
  }

  void setFaceImagePath(String path) {
    _faceImagePath = path;
    _updateReadyStatus();
    notifyListeners();
  }

  void _updateReadyStatus() {
    if (_videoPath != null && _faceImagePath != null) {
      _status = GenerationStatus.ready;
    }
  }

  Future<void> startGeneration() async {
    if (!canSubmit) return;

    _status = GenerationStatus.processing;
    _progress = 0.0;
    _errorMessage = null;
    _resultVideoPath = null;
    _currentStep = '正在连接服务器...';
    notifyListeners();

    try {
      // Phase 1: Check server health
      _updateProgress(0.05, '连接服务器中...');
      final healthy = await _api.healthCheck();
      if (!healthy) {
        throw ApiException(0, '无法连接到换脸服务器，请检查网络');
      }

      // Phase 2: Upload & swap (bulk of the work)
      _updateProgress(0.15, '上传素材中...');

      final resultPath = await _api.swapFace(
        sourcePath: _faceImagePath!,
        targetPath: _videoPath!,
        onProgress: (downloadProgress) {
          // Map download progress (0-1) to overall (0.2-0.95)
          _updateProgress(0.2 + downloadProgress * 0.75, '处理中...');
        },
      );

      _status = GenerationStatus.completed;
      _resultVideoPath = resultPath;
      _progress = 1.0;
      _currentStep = '生成完成';
    } on ApiException catch (e) {
      _status = GenerationStatus.failed;
      _errorMessage = e.message;
    } catch (e) {
      _status = GenerationStatus.failed;
      _errorMessage = '网络错误: ${e.toString()}';
    }
    notifyListeners();
  }

  void _updateProgress(double value, String step) {
    _progress = value;
    _currentStep = step;
    notifyListeners();
  }

  void reset() {
    _videoPath = null;
    _faceImagePath = null;
    _status = GenerationStatus.idle;
    _progress = 0.0;
    _errorMessage = null;
    _resultVideoPath = null;
    _currentStep = null;
    notifyListeners();
  }
}
