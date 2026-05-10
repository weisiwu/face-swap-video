import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../providers/generation_provider.dart';
import 'photo_grid_screen.dart';
import 'video_grid_screen.dart';

class GenerationScreen extends StatelessWidget {
  const GenerationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0A1A),
              Color(0xFF1A0F2E),
              Color(0xFF0D1117),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildVideoCard(),
                    const SizedBox(height: 16),
                    _buildFaceImageCard(),
                    const SizedBox(height: 24),
                    _buildActionArea(),
                    const SizedBox(height: 24),
                    _buildComplianceNotice(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.face_retouching_natural,
              color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),
        const Text(
          '视频换脸',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'AI 驱动的视频人脸替换工具',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoCard() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        final isSelected = provider.videoPath != null;
        return _buildSelectionCard(
          icon: Icons.videocam_rounded,
          iconColor: const Color(0xFF3B82F6),
          label: '源视频',
          hint: '选择需要换脸的视频文件',
          fileName: isSelected ? provider.videoFileName : null,
          isSelected: isSelected,
          onTap: () => _pickVideo(context),
        );
      },
    );
  }

  Widget _buildFaceImageCard() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        final isSelected = provider.faceImagePath != null;
        return GestureDetector(
          onTap: () => _pickFaceImage(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEC4899).withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFEC4899).withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // 缩略图 / 图标
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isSelected
                      ? ClipRRect(
                          key: const ValueKey('face-thumb'),
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(provider.faceImagePath!),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: Color(0xFFEC4899),
                                size: 22,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          key: const ValueKey('face-icon'),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFFEC4899),
                            size: 22,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '目标人脸',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isSelected
                            ? provider.faceImageFileName
                            : '选择用于替换的人脸照片',
                        style: TextStyle(
                          fontSize: 13,
                          color: isSelected
                              ? const Color(0xFFEC4899)
                              : Colors.white.withValues(alpha: 0.35),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 已选状态：换照片按钮
                if (isSelected)
                  GestureDetector(
                    onTap: () => _pickFaceImage(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '更换',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF472B6),
                        ),
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withValues(alpha: 0.2),
                    size: 20,
                  ),
              ],
            ),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? iconColor.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? iconColor.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
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
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fileName ?? hint,
                    style: TextStyle(
                      fontSize: 13,
                      color: fileName != null
                          ? iconColor
                          : Colors.white.withValues(alpha: 0.35),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.arrow_forward_ios,
              color: isSelected
                  ? iconColor
                  : Colors.white.withValues(alpha: 0.2),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionArea() {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        switch (provider.status) {
          case GenerationStatus.processing:
            return _buildProgressSection(provider);
          case GenerationStatus.completed:
            return _buildResultSection(provider);
          case GenerationStatus.failed:
            return _buildErrorSection(provider);
          default:
            return _buildSubmitButton(provider);
        }
      },
    );
  }

  Widget _buildSubmitButton(GenerationProvider provider) {
    final isReady = provider.canSubmit;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: isReady
            ? const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.05),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isReady
            ? [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isReady ? () => provider.startGeneration() : null,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: isReady
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.3),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  '开始换脸',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isReady
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection(GenerationProvider provider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFFA855F7)),
                ),
              ),
              const SizedBox(width: 14),
              const Text(
                'AI 换脸处理中...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: provider.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFA855F7)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${(provider.progress * 100).toInt()}%',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFA855F7),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (provider.currentStep != null) ...[
            const SizedBox(height: 8),
            Text(
              provider.currentStep!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultSection(GenerationProvider provider) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF059669).withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF34D399),
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '换脸完成！',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '视频已生成，可保存到相册或分享',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildResultButton(
                icon: Icons.download_rounded,
                label: '保存',
                color: const Color(0xFF3B82F6),
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildResultButton(
                icon: Icons.share_rounded,
                label: '分享',
                color: const Color(0xFF8B5CF6),
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildResultButton(
                icon: Icons.refresh_rounded,
                label: '再来一次',
                color: Colors.white.withValues(alpha: 0.1),
                onTap: () => provider.reset(),
              ),
            ),
          ],
        ),
      ],
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isTransparent ? color : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: isTransparent
              ? null
              : Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: isTransparent ? Colors.white : color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isTransparent ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorSection(GenerationProvider provider) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFDC2626).withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFF87171), size: 40),
              const SizedBox(height: 12),
              const Text(
                '处理失败',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (provider.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  provider.errorMessage!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSubmitButton(provider),
      ],
    );
  }

  Widget _buildComplianceNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 16, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '本工具仅用于授权素材的 AI 换脸。生成的内容带有 AI 水印标识，请勿用于冒充他人或传播虚假信息。',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.3),
                height: 1.4,
              ),
            ),
          ),
        ],
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
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
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
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
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
