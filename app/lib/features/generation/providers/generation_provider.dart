import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:face_swap_video/features/generation/services/api_service.dart';
import 'package:face_swap_video/core/services/notification_service.dart';
import 'package:face_swap_video/features/generation/services/video_upload_optimizer.dart';
import 'package:face_swap_video/features/media/utils/media_file_types.dart';
import 'package:face_swap_video/features/media/utils/selected_file_name.dart';
import 'package:face_swap_video/features/generation/utils/transfer_progress_label.dart';

enum GenerationStatus { idle, ready, processing, completed, failed }

class GenerationProvider extends ChangeNotifier {
  GenerationProvider({
    ApiService? api,
    VideoUploadOptimizer? videoUploadOptimizer,
  }) : _api = api ?? ApiService(),
       _videoUploadOptimizer =
           videoUploadOptimizer ?? VideoCompressUploadOptimizer();

  final ApiService _api;
  final VideoUploadOptimizer _videoUploadOptimizer;

  String? _videoPath;
  String? _faceImagePath;
  GenerationStatus _status = GenerationStatus.idle;
  double _progress = 0.0;
  String? _errorMessage;
  String? _resultVideoPath;
  String? _currentStep;
  int _generationRunId = 0;
  String? _currentVideoJobId;
  bool _isAppInBackground = false;
  bool _hasEnteredBackgroundDuringCurrentRun = false;
  int _progressPhaseId = 0;

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
  bool get hasSelectedMaterial => _videoPath != null || _faceImagePath != null;
  bool get shouldConfirmBeforeExit =>
      _status == GenerationStatus.processing || hasSelectedMaterial;

  bool get canSubmit =>
      _hasRequiredInputs && _status != GenerationStatus.processing;

  String get videoFileName => selectedFileName(_videoPath);
  String get faceImageFileName => selectedFileName(_faceImagePath);

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

      // Phase 2: shrink large target videos on-device before upload.
      final isVideoTarget = isVideoFilePath(_videoPath!);
      var uploadTargetPath = _videoPath!;
      if (isVideoTarget) {
        _updateProgress(0.08, '正在压缩视频，减少上传体积...', runId: runId);
        uploadTargetPath = await _videoUploadOptimizer.optimizeForUpload(
          _videoPath!,
          onProgress: (compressionProgress) {
            _updateProgress(
              0.08 + compressionProgress * 0.07,
              '正在压缩视频，减少上传体积...',
              runId: runId,
            );
          },
        );
        if (!_isActiveRun(runId)) return;
      }

      // Phase 3: Upload. The visible progress bar is stage-based: upload starts
      // at 0%, reaches 100%, then server processing starts from 0% again.
      final uploadPhaseId = _beginProgressPhase(uploadMaterialBaseLabel, runId);

      void handleUploadProgress(int sentBytes, int totalBytes) {
        if (!_isActiveRun(runId)) return;
        final uploadFraction = totalBytes > 0 ? sentBytes / totalBytes : 0.0;
        _updateProgress(
          uploadFraction.clamp(0.0, 1.0).toDouble(),
          formatUploadProgressLabel(
            uploadedBytes: sentBytes,
            totalBytes: totalBytes,
          ),
          runId: runId,
          phaseId: uploadPhaseId,
        );
      }

      String resultPath;
      if (isVideoTarget) {
        final jobId = await _api.swapVideoJob(
          sourcePath: _faceImagePath!,
          targetPath: uploadTargetPath,
          onUploadProgress: handleUploadProgress,
        );
        _currentVideoJobId = jobId;
        if (!_isActiveRun(runId)) return;
        _updateProgress(1.0, '素材上传完成', runId: runId, phaseId: uploadPhaseId);
        final processingPhaseId = _beginProgressPhase('服务器处理中...', runId);
        resultPath = await _api.pollSwapJob(
          jobId: jobId,
          onProgress: (processingProgress) {
            _updateProgress(
              processingProgress.clamp(0.0, 1.0).toDouble(),
              _isAppInBackground
                  ? '后台网络暂时不可用，继续等待服务器完成...'
                  : '服务器处理中，保持前台可查看进度...',
              runId: runId,
              phaseId: processingPhaseId,
            );
          },
        );
      } else {
        final processingPhaseId = _progressPhaseId + 1;
        resultPath = await _api.swapFace(
          sourcePath: _faceImagePath!,
          targetPath: _videoPath!,
          onUploadProgress: handleUploadProgress,
          onProgress: (processingProgress) {
            if (_progressPhaseId < processingPhaseId) {
              _updateProgress(
                1.0,
                '素材上传完成',
                runId: runId,
                phaseId: uploadPhaseId,
              );
              _beginProgressPhase('处理中...', runId);
            }
            _updateProgress(
              processingProgress.clamp(0.0, 1.0).toDouble(),
              '处理中...',
              runId: runId,
              phaseId: processingPhaseId,
            );
          },
        );
      }
      if (!_isActiveRun(runId)) return;

      _status = GenerationStatus.completed;
      _currentVideoJobId = null;
      _resultVideoPath = resultPath;
      _progress = 1.0;
      _currentStep = '生成完成';
      if (_isAppInBackground) {
        unawaited(NotificationService.showGenerationCompleted());
      }
    } on ApiException catch (e) {
      if (!_isActiveRun(runId)) return;
      _status = GenerationStatus.failed;
      _currentVideoJobId = null;
      _currentStep = '处理失败';
      _errorMessage = e.message;
      if (_isAppInBackground) {
        unawaited(NotificationService.showGenerationFailed(e.message));
      }
    } on TimeoutException {
      if (!_isActiveRun(runId)) return;
      _status = GenerationStatus.failed;
      _currentVideoJobId = null;
      _currentStep = '处理失败';
      _errorMessage = '处理超时，请稍后重试';
      if (_isAppInBackground) {
        unawaited(NotificationService.showGenerationFailed(_errorMessage!));
      }
    } catch (e) {
      if (!_isActiveRun(runId)) return;
      _status = GenerationStatus.failed;
      _currentVideoJobId = null;
      _currentStep = '处理失败';
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

  int _beginProgressPhase(String step, int runId) {
    if (!_isActiveRun(runId)) return _progressPhaseId;
    _progressPhaseId++;
    _progress = 0.0;
    _currentStep = step;
    notifyListeners();
    return _progressPhaseId;
  }

  void _updateProgress(double value, String step, {int? runId, int? phaseId}) {
    if (runId != null && !_isActiveRun(runId)) return;
    if (phaseId != null && phaseId != _progressPhaseId) return;

    final nextProgress = value.clamp(0.0, 1.0).toDouble();
    if (_status == GenerationStatus.processing && nextProgress < _progress) {
      return;
    }

    _progress = nextProgress;
    _currentStep = step;
    notifyListeners();
  }

  void cancelGeneration() {
    if (_status != GenerationStatus.processing) return;

    _generationRunId++;
    final jobId = _currentVideoJobId;
    _currentVideoJobId = null;
    if (jobId != null) {
      unawaited(_api.cancelSwapJob(jobId));
    }
    unawaited(_videoUploadOptimizer.cancel());
    _status = _inputAwareIdleStatus;
    _clearTransientResultState();
    notifyListeners();
  }

  void dismissError() {
    if (_status != GenerationStatus.failed) return;

    _status = _inputAwareIdleStatus;
    _clearTransientResultState();
    notifyListeners();
  }

  void reset() {
    _videoPath = null;
    _faceImagePath = null;
    _status = GenerationStatus.idle;
    _clearTransientResultState();
    notifyListeners();
  }

  @visibleForTesting
  void debugSetProcessingForTest() {
    _status = GenerationStatus.processing;
    _progress = 0.2;
    _currentStep = '测试处理中';
    notifyListeners();
  }

  void _clearTransientResultState() {
    _progress = 0.0;
    _errorMessage = null;
    _resultVideoPath = null;
    _currentStep = null;
    _hasEnteredBackgroundDuringCurrentRun = false;
  }
}
