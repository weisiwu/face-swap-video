import 'package:flutter/material.dart';
import 'package:face_swap_video/features/generation/widgets/result_video_preview.dart';

typedef ResultSaveCallback = Future<void> Function(BuildContext dialogContext);

class ResultPreviewDialog extends StatefulWidget {
  const ResultPreviewDialog({
    super.key,
    required this.resultPath,
    required this.onSave,
  });

  final String resultPath;
  final ResultSaveCallback onSave;

  @override
  State<ResultPreviewDialog> createState() => _ResultPreviewDialogState();
}

class _ResultPreviewDialogState extends State<ResultPreviewDialog> {
  bool _savingResult = false;

  @override
  Widget build(BuildContext context) {
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
                    color: const Color(0xFF059669).withValues(alpha: 0.18),
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
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ResultVideoPreview(resultPath: widget.resultPath),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: _savingResult
                    ? null
                    : () async {
                        setState(() => _savingResult = true);
                        await widget.onSave(context);
                        if (mounted) {
                          setState(() => _savingResult = false);
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
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
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
  }
}
