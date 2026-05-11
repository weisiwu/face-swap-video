import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:face_swap_video/features/generation/providers/generation_provider.dart';

typedef GenerationCancelCallback =
    Future<void> Function(
      BuildContext dialogContext,
      GenerationProvider provider,
    );

class GenerationProgressDialog extends StatelessWidget {
  const GenerationProgressDialog({
    super.key,
    required this.onCancelRequested,
    required this.onBackExit,
  });

  final GenerationCancelCallback onCancelRequested;
  final Future<void> Function() onBackExit;

  @override
  Widget build(BuildContext context) {
    return Consumer<GenerationProvider>(
      builder: (context, currentProvider, _) {
        if (currentProvider.status != GenerationStatus.processing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }

        // ignore: deprecated_member_use -- DialogRoute hardware-back interception still relies on WillPopScope here.
        return WillPopScope(
          onWillPop: () async {
            await onBackExit();
            return false;
          },
          child: Dialog(
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
                      onPressed: () =>
                          onCancelRequested(context, currentProvider),
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
          ),
        );
      },
    );
  }
}
