import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:face_swap_video/features/generation/providers/generation_provider.dart';

typedef GenerationSubmitCallback =
    Future<void> Function(GenerationProvider provider);
typedef GenerationPreviewCallback = void Function(GenerationProvider provider);

class GenerationStickyFooter extends StatelessWidget {
  const GenerationStickyFooter({
    super.key,
    required this.appVersion,
    required this.onSubmit,
    required this.onPreviewResult,
  });

  final String appVersion;
  final GenerationSubmitCallback onSubmit;
  final GenerationPreviewCallback onPreviewResult;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            key: const ValueKey('generation-sticky-bottom-footer'),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _ComplianceNotice(),
                const SizedBox(height: 10),
                _VersionFooter(appVersion: appVersion),
                const SizedBox(height: 10),
                _ActionArea(
                  onSubmit: onSubmit,
                  onPreviewResult: onPreviewResult,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({required this.onSubmit, required this.onPreviewResult});

  final GenerationSubmitCallback onSubmit;
  final GenerationPreviewCallback onPreviewResult;

  @override
  Widget build(BuildContext context) {
    return Consumer<GenerationProvider>(
      builder: (context, provider, _) {
        switch (provider.status) {
          case GenerationStatus.processing:
            return const SizedBox.shrink();
          case GenerationStatus.completed:
            return _ResultButton(
              icon: Icons.visibility_rounded,
              label: '预览并保存',
              color: const Color(0xFF3B82F6),
              onTap: () => onPreviewResult(provider),
            );
          case GenerationStatus.failed:
            return _SubmitButton(provider: provider, onSubmit: onSubmit);
          default:
            return _SubmitButton(provider: provider, onSubmit: onSubmit);
        }
      },
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.provider, required this.onSubmit});

  final GenerationProvider provider;
  final GenerationSubmitCallback onSubmit;

  @override
  Widget build(BuildContext context) {
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
          onTap: isReady ? () => onSubmit(provider) : null,
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
}

class _ResultButton extends StatelessWidget {
  const _ResultButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
}

class _ComplianceNotice extends StatelessWidget {
  const _ComplianceNotice();

  @override
  Widget build(BuildContext context) {
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
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter({required this.appVersion});

  final String appVersion;

  @override
  Widget build(BuildContext context) {
    return Text(
      'v$appVersion',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Colors.white.withValues(alpha: 0.28),
      ),
    );
  }
}
