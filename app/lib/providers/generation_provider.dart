import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/media_file_types.dart';

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
  int _generationRunId = 0;
  bool _isAppInBackground = false;
  bool _hasEnteredBackgroundDuringCurrentRun = false;

  // Getters
  String? get videoPath => _videoPath;
  String? get faceImagePath => _faceImagePath;
  GenerationStatus get status => _status;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get resultVideoPath => _resultVideoPath;
  String? get currentStep => _currentStep;
  bool get isAppInBackground => _isAppInBackground;
  bool get isBackgroundConversionActive =>
      _status == GenerationStatus.processing && _isAppInBackground;

  bool get canSubmit =>
      _hasRequiredInputs && _status != GenerationStatus.processing;

  String get videoFileName => _videoPath?.split('/').last ?? '未选择';
  String get faceImageFileName => _faceImagePath?.split('/').last ?? '未选择';

  bool get _hasRequiredInputs => _videoPath != null && _faceImagePath != null;
  GenerationStatus get _inputAwareIdleStatus =>
      _hasRequiredInputs ? GenerationStatus.ready : GenerationStatus.idle;

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
    if (_hasRequiredInputs) {
      _status = GenerationStatus.ready;
    }
  }

  Future<void> startGeneration() async {
    if (!canSubmit) return;

    final runId = ++_generationRunId;
    _hasEnteredBackgroundDuringCurrentRun = false;
    _status = GenerationStatus.processing;
    _progress = 0.0;
    _errorMessage = null;
    _resultVideoPath = null;
    _currentStep = '正在连接服务器...';
    notifyListeners();

    try {
      // Phase 1: Check server health
      _updateProgress(0.05, '连接服务器中...', runId: runId);
      final healthy = await _api.healthCheck();
      if (!_isActiveRun(runId)) return;
      if (!healthy) {
        throw ApiException(0, '无法连接到换脸服务器，请检查网络');
      }

      // Phase 2: Upload & swap (bulk of the work)
      _updateProgress(0.15, '上传素材中...', runId: runId);

      String resultPath;
      if (isVideoFilePath(_videoPath!)) {
        final jobId = await _api.swapVideoJob(
          sourcePath: _faceImagePath!,
          targetPath: _videoPath!,
        );
        if (!_isActiveRun(runId)) return;
        _updateProgress(0.25, '素材已上传，服务器处理中...', runId: runId);
        resultPath = await _api.pollSwapJob(
          jobId: jobId,
          onProgress: (downloadProgress) {
            _updateProgress(
              0.3 + downloadProgress * 0.65,
              _isAppInBackground
                  ? '后台网络暂时不可用，继续等待服务器完成...'
                  : '服务器处理中，保持前台可查看进度...',
              runId: runId,
            );
          },
        );
      } else {
        resultPath = await _api.swapFace(
          sourcePath: _faceImagePath!,
          targetPath: _videoPath!,
          onProgress: (downloadProgress) {
            // Map download progress (0-1) to overall (0.2-0.95)
            _updateProgress(
              0.2 + downloadProgress * 0.75,
              '处理中...',
              runId: runId,
            );
          },
        );
      }
      if (!_isActiveRun(runId)) return;

      _status = GenerationStatus.completed;
      _resultVideoPath = resultPath;
      _progress = 1.0;
      _currentStep = '生成完成';
      if (_isAppInBackground) {
        unawaited(NotificationService.showGenerationCompleted());
      }
    } on ApiException catch (e) {
      if (!_isActiveRun(runId)) return;
      _status = GenerationStatus.failed;
      _errorMessage = e.message;
      if (_isAppInBackground) {
        unawaited(NotificationService.showGenerationFailed(e.message));
      }
    } catch (e) {
      if (!_isActiveRun(runId)) return;
      _status = GenerationStatus.failed;
      _errorMessage = '网络连接暂时不可用，请稍后重试';
      if (_isAppInBackground) {
        unawaited(NotificationService.showGenerationFailed(_errorMessage!));
      }
    }
    notifyListeners();
  }

  bool _isActiveRun(int runId) =>
      _generationRunId == runId && _status == GenerationStatus.processing;

  void setAppLifecycleInBackground(bool isBackground) {
    if (_isAppInBackground == isBackground) return;

    _isAppInBackground = isBackground;
    if (_status == GenerationStatus.processing) {
      if (isBackground) {
        _hasEnteredBackgroundDuringCurrentRun = true;
        _currentStep = '应用已切到后台，继续后台转换，完成后会通知你';
      } else if (_hasEnteredBackgroundDuringCurrentRun) {
        _currentStep = '已回到前台，继续转换中...';
      }
      notifyListeners();
    }
  }

  void _updateProgress(double value, String step, {int? runId}) {
    if (runId != null && !_isActiveRun(runId)) return;
    _progress = value;
    _currentStep = step;
    notifyListeners();
  }

  void cancelGeneration() {
    if (_status != GenerationStatus.processing) return;

    _generationRunId++;
    _status = _inputAwareIdleStatus;
    _progress = 0.0;
    _errorMessage = null;
    _resultVideoPath = null;
    _currentStep = null;
    _hasEnteredBackgroundDuringCurrentRun = false;
    notifyListeners();
  }

  void dismissError() {
    if (_status != GenerationStatus.failed) return;

    _status = _inputAwareIdleStatus;
    _progress = 0.0;
    _errorMessage = null;
    _currentStep = null;
    _hasEnteredBackgroundDuringCurrentRun = false;
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
    _hasEnteredBackgroundDuringCurrentRun = false;
    notifyListeners();
  }
}
