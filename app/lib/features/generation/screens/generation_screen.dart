import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:async';
import 'dart:io';
import 'package:face_swap_video/features/auth/providers/auth_provider.dart';
import 'package:face_swap_video/features/generation/providers/generation_provider.dart';
import 'package:face_swap_video/features/generation/widgets/generation_header.dart';
import 'package:face_swap_video/features/generation/widgets/generation_progress_dialog.dart';
import 'package:face_swap_video/features/generation/widgets/material_picker_card.dart';
import 'package:face_swap_video/features/generation/widgets/result_preview_dialog.dart';
import 'package:face_swap_video/features/generation/widgets/sticky_generation_footer.dart';
import 'package:face_swap_video/features/generation/widgets/anime_aura_painter.dart';
import 'package:face_swap_video/features/auth/screens/login_screen.dart';
import 'package:face_swap_video/features/media/screens/photo_grid_screen.dart';
import 'package:face_swap_video/features/media/screens/video_grid_screen.dart';

const String _appVersion = '1.7.5';

class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key, this.onExitApp = SystemNavigator.pop});

  final FutureOr<void> Function() onExitApp;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen> {
  static const double _homeLogoSize = 92;
  static const double _targetFaceTopPhysicalPx = 253;

  GenerationProvider? _provider;
  bool _errorDialogVisible = false;
  bool _processingDialogVisible = false;
  bool _completionDialogVisible = false;
  bool _exitDialogVisible = false;
  String? _lastErrorDialogMessage;
  String? _lastCompletionDialogPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<GenerationProvider>();
    if (_provider == provider) return;

    _provider?.removeListener(_handleProviderChange);
    _provider = provider;
    _provider?.addListener(_handleProviderChange);
    _handleProviderChange();
  }

  @override
  void dispose() {
    _provider?.removeListener(_handleProviderChange);
    super.dispose();
  }

  void _handleProviderChange() {
    final provider = _provider;
    if (provider == null || !mounted) return;

    if (provider.status == GenerationStatus.processing) {
      _lastErrorDialogMessage = null;
      if (!_processingDialogVisible) {
        _processingDialogVisible = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && provider.status == GenerationStatus.processing) {
            _showProcessingDialog(provider);
          } else {
            _processingDialogVisible = false;
          }
        });
      }
    } else if (_processingDialogVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _processingDialogVisible) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      });
    }

    if (provider.status == GenerationStatus.failed && !_errorDialogVisible) {
      final message = provider.errorMessage ?? '处理过程中发生未知错误';
      if (_lastErrorDialogMessage == message) return;
      _lastErrorDialogMessage = message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && provider.status == GenerationStatus.failed) {
          _showErrorDialog(provider, message);
        }
      });
    }

    if (provider.status == GenerationStatus.completed &&
        provider.resultVideoPath != null &&
        !_completionDialogVisible &&
        _lastCompletionDialogPath != provider.resultVideoPath) {
      _lastCompletionDialogPath = provider.resultVideoPath;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 先让“处理中”弹框完成关闭，再自动弹出结果预览，避免两个弹框抢同一个 Navigator。
        if (_processingDialogVisible) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
        if (mounted && provider.status == GenerationStatus.completed) {
          _showCompletionDialog(provider);
        }
      });
    }
  }

  Future<void> _showProcessingDialog(GenerationProvider provider) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GenerationProgressDialog(
        onCancelRequested: _confirmCancelGeneration,
        onBackExit: _handleBackExit,
      ),
    );

    _processingDialogVisible = false;
  }

  Future<void> _confirmCancelGeneration(
    BuildContext dialogContext,
    GenerationProvider provider,
  ) async {
    final shouldCancel = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: true,
      builder: (confirmContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17111F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          title: const Text(
            '是否取消处理？',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: Text(
            '取消后本次换脸任务不会继续展示结果，需要重新点击开始换脸。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('继续等待'),
            ),
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              child: const Text(
                '取消处理',
                style: TextStyle(color: Color(0xFFF87171)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldCancel == true) {
      provider.cancelGeneration();
      if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop();
      }
    }
  }

  Future<void> _showErrorDialog(
    GenerationProvider provider,
    String message,
  ) async {
    if (_errorDialogVisible) return;
    _errorDialogVisible = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF17111F),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFDC2626).withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFF87171),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '处理失败',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('关闭'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          provider.dismissError();
                          _handleSubmit(provider);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    _errorDialogVisible = false;
    if (mounted && provider.status == GenerationStatus.failed) {
      provider.dismissError();
    }
  }

  Future<void> _showCompletionDialog(GenerationProvider provider) async {
    if (_completionDialogVisible) return;
    final resultPath = provider.resultVideoPath;
    if (resultPath == null || resultPath.isEmpty) return;

    _completionDialogVisible = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ResultPreviewDialog(
        resultPath: resultPath,
        onSave: (dialogContext) => _saveResultVideo(provider, dialogContext),
      ),
    );

    _completionDialogVisible = false;
  }

  Future<void> _saveResultVideo(
    GenerationProvider provider, [
    BuildContext? dialogContext,
  ]) async {
    final resultPath = provider.resultVideoPath;
    if (resultPath == null || resultPath.isEmpty) {
      await _showSaveMessageDialog('保存失败', '未找到生成的视频文件，请重新生成后再试。');
      return;
    }

    final file = File(resultPath);
    if (!await file.exists()) {
      await _showSaveMessageDialog('保存失败', '生成的视频文件不存在，请重新生成后再试。');
      return;
    }

    try {
      final title =
          'face_swap_${DateTime.now().millisecondsSinceEpoch}.${resultPath.split('.').last}';
      await PhotoManager.editor.saveVideo(file, title: title);

      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      if (mounted) {
        await _showSaveSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        await _showSaveMessageDialog('保存失败', '无法保存到相册：$e');
      }
    } finally {
      // Saving button state is owned by ResultPreviewDialog.
    }
  }

  Future<void> _showSaveSuccessDialog() {
    return _showSaveMessageDialog('保存成功', '视频已保存到系统相册。');
  }

  Future<void> _showSaveMessageDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17111F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoTopInset = _targetLogoTopInset(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050510),
        body: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: AnimeAuraPainter()),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(20, logoTopInset, 20, 216),
                      child: Column(
                        children: [
                          GenerationHeader(
                            logoSize: _homeLogoSize,
                            onLogout: () =>
                                context.read<AuthProvider>().logout(),
                          ),
                          const SizedBox(height: 10),
                          const GenerationAppTitle(),
                          const SizedBox(height: 14),
                          const GenerationWorkflowChips(),
                          const SizedBox(height: 18),
                          _buildVideoCard(),
                          const SizedBox(height: 14),
                          _buildFaceImageCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 260,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00050510),
                        Color(0xDD050510),
                        Color(0xFF050510),
                      ],
                      stops: [0.0, 0.58, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GenerationStickyFooter(
                appVersion: _appVersion,
                onSubmit: _handleSubmit,
                onPreviewResult: _showCompletionDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBackExit() async {
    if (_exitDialogVisible) return;

    final provider = context.read<GenerationProvider>();
    if (!provider.shouldConfirmBeforeExit) {
      await widget.onExitApp();
      return;
    }

    final isProcessing = provider.status == GenerationStatus.processing;
    _exitDialogVisible = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF17111F),
        title: const Text('确定要退出吗？'),
        content: Text(
          isProcessing
              ? '正在处理，退出后当前处理进度可能无法继续展示。确定退出应用吗？'
              : '已选择的素材和当前填写内容将不会保留。确定退出应用吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    _exitDialogVisible = false;
    if (shouldExit == true) {
      await widget.onExitApp();
    }
  }

  double _targetLogoTopInset(BuildContext context) {
    final media = MediaQuery.of(context);
    final faceTopInsideLogo = _homeLogoSize * (0.5 - 0.19 * 0.91);
    final top =
        (_targetFaceTopPhysicalPx / media.devicePixelRatio) -
        media.padding.top -
        faceTopInsideLogo;
    return top.clamp(0.0, 96.0);
  }

  Widget _buildVideoCard() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        final isSelected = provider.videoPath != null;
        return MaterialPickerCard(
          icon: Icons.videocam_rounded,
          iconColor: const Color(0xFF72F2FF),
          label: '源视频',
          hint: '选择需要换脸的视频文件',
          fileName: isSelected ? provider.videoFileName : null,
          isSelected: isSelected,
          onTap: () => _pickVideo(context),
          leading: isSelected && provider.videoPath != null
              ? SourceVideoThumbnail(videoPath: provider.videoPath!)
              : null,
        );
      },
    );
  }

  Widget _buildFaceImageCard() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        final isSelected = provider.faceImagePath != null;
        return MaterialPickerCard(
          icon: Icons.person_rounded,
          iconColor: const Color(0xFFFF7ACD),
          label: '目标人脸',
          hint: '选择用于替换的人脸照片',
          fileName: isSelected ? provider.faceImageFileName : null,
          isSelected: isSelected,
          onTap: () => _pickFaceImage(context),
          leading: isSelected && provider.faceImagePath != null
              ? FaceImageThumbnail(imagePath: provider.faceImagePath!)
              : null,
        );
      },
    );
  }

  Future<void> _handleSubmit(GenerationProvider provider) async {
    final isAuthenticated = context.read<AuthProvider>().isAuthenticated;
    if (isAuthenticated) {
      await provider.startGeneration();
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(key: ValueKey('login')),
      ),
    );
  }

  Future<void> _pickVideo(BuildContext context) async {
    // 导航到选视频页面，等待返回路径
    final path = await Navigator.of(context).push<String>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const VideoGridScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );

    if (path != null && context.mounted) {
      context.read<GenerationProvider>().setVideoPath(path);
    }
  }

  Future<void> _pickFaceImage(BuildContext context) async {
    // 导航到选照片页面，等待返回路径
    final path = await Navigator.of(context).push<String>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PhotoGridScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );

    if (path != null && context.mounted) {
      context.read<GenerationProvider>().setFaceImagePath(path);
    }
  }
}
