import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:face_swap_video/features/auth/providers/auth_provider.dart';
import 'package:face_swap_video/core/widgets/app_face_swap_logo.dart';

class GenerationHeader extends StatelessWidget {
  const GenerationHeader({
    super.key,
    required this.logoSize,
    required this.onLogout,
  });

  final double logoSize;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 86),
        Expanded(
          child: Center(child: AppFaceSwapLogo(size: logoSize)),
        ),
        SizedBox(
          width: 86,
          child: Align(child: _AccountEntry(onLogout: onLogout)),
        ),
      ],
    );
  }
}

class _AccountEntry extends StatelessWidget {
  const _AccountEntry({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.select<AuthProvider, bool>(
      (provider) => provider.isAuthenticated,
    );
    if (!isAuthenticated) {
      return const SizedBox.shrink();
    }

    final displayPhone = context.select<AuthProvider, String>(
      (provider) => provider.displayPhone,
    );
    return InkWell(
      key: const ValueKey('generation-account-entry'),
      borderRadius: BorderRadius.circular(999),
      onLongPress: onLogout,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Text(
          displayPhone,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.74),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class GenerationAppTitle extends StatelessWidget {
  const GenerationAppTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      '爆肝AI',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
      ),
    );
  }
}

class GenerationWorkflowChips extends StatelessWidget {
  const GenerationWorkflowChips({super.key});

  @override
  Widget build(BuildContext context) {
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
}
