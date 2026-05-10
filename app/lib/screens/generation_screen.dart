import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import '../providers/generation_provider.dart';
import 'photo_grid_screen.dart';
import 'video_grid_screen.dart';

const String _appVersion = '1.4.0';

class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key});

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
  bool _savingResult = false;
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
      builder: (dialogContext) {
        return Consumer<GenerationProvider>(
          builder: (context, currentProvider, _) {
            if (currentProvider.status != GenerationStatus.processing) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
              });
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF17111F),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
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
                        onPressed: () => _confirmCancelGeneration(
                          dialogContext,
                          currentProvider,
                        ),
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
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFA855F7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'AI 换脸处理中...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      currentProvider.currentStep ?? '请稍候，正在处理素材',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: currentProvider.progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFA855F7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(currentProvider.progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA855F7),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
                          provider.startGeneration();
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
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 36),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF17111F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF059669).withValues(alpha: 0.35),
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
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF059669,
                            ).withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF34D399),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '换脸完成！',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ResultVideoPreview(resultPath: resultPath),
                    const SizedBox(height: 10),
                    Text(
                      '先预览生成结果，确认满意后再保存到系统相册。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: _savingResult
                            ? null
                            : () async {
                                setDialogState(() => _savingResult = true);
                                await _saveResultVideo(provider, dialogContext);
                                if (dialogContext.mounted) {
                                  setDialogState(() => _savingResult = false);
                                }
                              },
                        icon: Icon(
                          _savingResult
                              ? Icons.hourglass_top_rounded
                              : Icons.download_rounded,
                          size: 18,
                        ),
                        label: Text(_savingResult ? '保存中...' : '保存到相册'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: 0.08,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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

    if (mounted) {
      setState(() => _savingResult = true);
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
      if (mounted) {
        setState(() => _savingResult = false);
      }
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
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _AnimeAuraPainter()),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20, logoTopInset, 20, 28),
                    child: Column(
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 10),
                        _buildAppTitle(),
                        const SizedBox(height: 14),
                        _buildWorkflowChips(),
                        const SizedBox(height: 18),
                        _buildVideoCard(),
                        const SizedBox(height: 14),
                        _buildFaceImageCard(),
                        const SizedBox(height: 22),
                        _buildActionArea(),
                        const SizedBox(height: 18),
                        _buildComplianceNotice(),
                        const SizedBox(height: 12),
                        _buildVersionFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _buildHeader() {
    return const Center(child: _HomeFaceSwapLogo(size: 92));
  }

  Widget _buildAppTitle() {
    return const Text(
      '视频换脸',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
      ),
    );
  }

  Widget _buildWorkflowChips() {
    const chips = [
      ('1 上传视频', Color(0xFF72F2FF)),
      ('2 选择人脸', Color(0xFFFF7ACD)),
      ('3 AI 换脸', Color(0xFFB8FF6A)),
    ];
    return Row(
      children: [
        for (final chip in chips) ...[
          Expanded(
            child: Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chip.$2.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: chip.$2.withValues(alpha: 0.22)),
              ),
              child: Text(
                chip.$1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: chip.$2,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (chip != chips.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildVideoCard() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        final isSelected = provider.videoPath != null;
        return _buildSelectionCard(
          icon: Icons.videocam_rounded,
          iconColor: const Color(0xFF72F2FF),
          label: '源视频',
          hint: '选择需要换脸的视频文件',
          fileName: isSelected ? provider.videoFileName : null,
          isSelected: isSelected,
          onTap: () => _pickVideo(context),
          leading: isSelected && provider.videoPath != null
              ? _buildSourceVideoThumbnail(provider.videoPath!)
              : null,
        );
      },
    );
  }

  Widget _buildFaceImageCard() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        final isSelected = provider.faceImagePath != null;
        return _buildSelectionCard(
          icon: Icons.person_rounded,
          iconColor: const Color(0xFFFF7ACD),
          label: '目标人脸',
          hint: '选择用于替换的人脸照片',
          fileName: isSelected ? provider.faceImageFileName : null,
          isSelected: isSelected,
          onTap: () => _pickFaceImage(context),
          leading: isSelected && provider.faceImagePath != null
              ? _buildFaceImageThumbnail(provider.faceImagePath!)
              : null,
        );
      },
    );
  }

  Widget _buildFaceImageThumbnail(String imagePath) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.file(
        File(imagePath),
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFFF7ACD).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.person_rounded,
            color: Color(0xFFFF7ACD),
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceVideoThumbnail(String videoPath) {
    return FutureBuilder<Uint8List?>(
      key: ValueKey('source-video-thumb-$videoPath'),
      future: VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 128,
        quality: 75,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.memory(
                  snapshot.data!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.videocam_rounded,
            color: Color(0xFF3B82F6),
            size: 22,
          ),
        );
      },
    );
  }

  Widget _buildSelectionCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String hint,
    required String? fileName,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? leading,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isSelected
                ? iconColor.withValues(alpha: 0.13)
                : Colors.white.withValues(alpha: 0.065),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected
                  ? iconColor.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.11),
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? iconColor : Colors.black).withValues(
                  alpha: isSelected ? 0.22 : 0.24,
                ),
                blurRadius: isSelected ? 28 : 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    leading ??
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                iconColor.withValues(alpha: 0.36),
                                iconColor.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Icon(icon, color: iconColor, size: 24),
                        ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            fileName ?? hint,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: fileName != null
                                  ? iconColor
                                  : Colors.white.withValues(alpha: 0.43),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? iconColor.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        color: isSelected
                            ? iconColor
                            : Colors.white.withValues(alpha: 0.42),
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionArea() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        switch (provider.status) {
          case GenerationStatus.processing:
            return const SizedBox.shrink();
          case GenerationStatus.completed:
            return _buildResultSection(provider);
          case GenerationStatus.failed:
            return _buildSubmitButton(provider);
          default:
            return _buildSubmitButton(provider);
        }
      },
    );
  }

  Widget _buildSubmitButton(GenerationProvider provider) {
    final isReady = provider.canSubmit;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        gradient: isReady
            ? const LinearGradient(
                colors: [
                  Color(0xFFFF7ACD),
                  Color(0xFF8B5CF6),
                  Color(0xFF72F2FF),
                ],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: isReady
            ? [
                BoxShadow(
                  color: const Color(0xFFFF7ACD).withValues(alpha: 0.30),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isReady ? () => provider.startGeneration() : null,
          borderRadius: BorderRadius.circular(999),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: isReady
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.32),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  isReady ? '一键开始换脸' : '准备好素材后开始生成',
                  style: TextStyle(
                    fontSize: isReady ? 17 : 15,
                    fontWeight: FontWeight.w900,
                    color: isReady
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.36),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultSection(GenerationProvider provider) {
    return _buildResultButton(
      icon: Icons.visibility_rounded,
      label: '预览并保存',
      color: const Color(0xFF3B82F6),
      onTap: () => _showCompletionDialog(provider),
    );
  }

  Widget _buildResultButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isTransparent = color.a < 1;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isTransparent ? color : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: isTransparent
              ? null
              : Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isTransparent ? Colors.white : color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isTransparent ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceNotice() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFB8FF6A).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 15,
                  color: Color(0xFFB8FF6A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '仅处理授权素材。生成内容带有 AI 提示，请勿用于冒充他人或传播虚假信息。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.42),
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersionFooter() {
    return Text(
      'v$_appVersion',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Colors.white.withValues(alpha: 0.28),
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

class _HomeFaceSwapLogo extends StatelessWidget {
  const _HomeFaceSwapLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _HomeFaceSwapLogoPainter()),
    );
  }
}

class _HomeFaceSwapLogoPainter extends CustomPainter {
  const _HomeFaceSwapLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pink = const Color(0xFFFF7ACD);
    final cyan = const Color(0xFF72F2FF);
    final violet = const Color(0xFF8B5CF6);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          pink.withValues(alpha: 0.32),
          cyan.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, size.width * 0.42, glowPaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.42),
      -math.pi * 0.12,
      math.pi * 1.25,
      false,
      orbitPaint..color = cyan.withValues(alpha: 0.68),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.34),
      math.pi * 1.04,
      -math.pi * 1.18,
      false,
      orbitPaint..color = pink.withValues(alpha: 0.75),
    );

    final left = Offset(size.width * 0.53, size.height * 0.5);
    final right = Offset(size.width * 0.47, size.height * 0.5);
    _drawAnimeFace(canvas, left, size.width * 0.19, pink, 0.08);
    _drawAnimeFace(canvas, right, size.width * 0.19, cyan, -0.08);

    final sparkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = violet.withValues(alpha: 0.78);
    for (var i = 0; i < 6; i++) {
      final angle = math.pi * 2 + i * math.pi / 3;
      final r = size.width * (0.23 + 0.12 * ((i % 2) + 1) / 2);
      final p = center + Offset(math.cos(angle), math.sin(angle)) * r;
      canvas.drawCircle(p, 2.1, sparkPaint);
    }
  }

  void _drawAnimeFace(
    Canvas canvas,
    Offset c,
    double r,
    Color color,
    double tilt,
  ) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    final facePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFF6F8);
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.9);
    final hairPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.82);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: r * 1.65, height: r * 1.82),
        Radius.circular(r * 0.72),
      ),
      facePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: r * 1.65, height: r * 1.82),
        Radius.circular(r * 0.72),
      ),
      edgePaint,
    );
    final hair = Path()
      ..moveTo(-r * 0.82, -r * 0.2)
      ..quadraticBezierTo(-r * 0.55, -r * 1.0, 0, -r * 0.9)
      ..quadraticBezierTo(r * 0.65, -r * 0.92, r * 0.82, -r * 0.1)
      ..quadraticBezierTo(r * 0.28, -r * 0.34, -r * 0.1, -r * 0.22)
      ..quadraticBezierTo(-r * 0.45, -r * 0.08, -r * 0.82, -r * 0.2)
      ..close();
    canvas.drawPath(hair, hairPaint);

    final eyePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF17111F);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.28, r * 0.08),
        width: r * 0.18,
        height: r * 0.34,
      ),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(r * 0.28, r * 0.08),
        width: r * 0.18,
        height: r * 0.34,
      ),
      eyePaint,
    );
    canvas.drawCircle(
      Offset(-r * 0.24, -r * 0.02),
      r * 0.035,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(r * 0.32, -r * 0.02),
      r * 0.035,
      Paint()..color = Colors.white,
    );
    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF17111F).withValues(alpha: 0.55);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(0, r * 0.34),
        width: r * 0.34,
        height: r * 0.18,
      ),
      0,
      math.pi,
      false,
      mouth,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HomeFaceSwapLogoPainter oldDelegate) => false;
}

class _AnimeAuraPainter extends CustomPainter {
  const _AnimeAuraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF050510), Color(0xFF171126), Color(0xFF050510)],
        ).createShader(rect),
    );

    void glow(Offset center, double radius, Color color) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.24), Colors.transparent],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    glow(
      Offset(size.width * 0.18, size.height * 0.10),
      size.width * 0.58,
      const Color(0xFFFF7ACD),
    );
    glow(
      Offset(size.width * 0.88, size.height * 0.28),
      size.width * 0.48,
      const Color(0xFF72F2FF),
    );
    glow(
      Offset(size.width * 0.50, size.height * 0.92),
      size.width * 0.60,
      const Color(0xFF8B5CF6),
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.035);
    for (var y = 0.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 20), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimeAuraPainter oldDelegate) => false;
}

class _ResultVideoPreview extends StatefulWidget {
  const _ResultVideoPreview({required this.resultPath});

  final String resultPath;

  @override
  State<_ResultVideoPreview> createState() => _ResultVideoPreviewState();
}

class _ResultVideoPreviewState extends State<_ResultVideoPreview> {
  late final VideoPlayerController _controller;
  bool _initializing = true;
  bool _handlingPreviewCompletion = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.resultPath));
    _controller.addListener(_handleControllerChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(false);
      if (mounted) {
        setState(() => _initializing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorMessage = '视频预览加载失败';
        });
      }
    }
  }

  void _handleControllerChanged() {
    _handlePreviewCompleted();
    if (mounted) setState(() {});
  }

  void _handlePreviewCompleted() {
    final value = _controller.value;
    if (!value.isInitialized ||
        !value.isPlaying ||
        value.duration == Duration.zero ||
        _handlingPreviewCompletion) {
      return;
    }
    if (value.position >= value.duration) {
      _handlingPreviewCompletion = true;
      unawaited(
        _controller.pause().whenComplete(() {
          _handlingPreviewCompletion = false;
        }),
      );
    }
  }

  Future<void> _togglePlayback() async {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      if (_controller.value.position >= _controller.value.duration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller.value.isInitialized;
    final isPlaying = isReady && _controller.value.isPlaying;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: GestureDetector(
          onTap: isReady ? _togglePlayback : null,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (isReady)
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                )
              else
                Container(
                  color: Colors.white.withValues(alpha: 0.06),
                  child: Center(
                    child: _initializing
                        ? const CircularProgressIndicator(
                            color: Color(0xFF34D399),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.movie_creation_outlined,
                                size: 42,
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.04),
                      Colors.black.withValues(alpha: 0.34),
                    ],
                  ),
                ),
              ),
              if (!isPlaying)
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.46),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              if (isReady)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: EdgeInsets.zero,
                    colors: VideoProgressColors(
                      playedColor: const Color(0xFF34D399),
                      bufferedColor: Colors.white.withValues(alpha: 0.32),
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Row(
                  children: [
                    Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: const Color(0xFF34D399),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isPlaying ? '点击暂停预览' : '点击播放预览',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
