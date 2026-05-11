import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class MaterialPickerCard extends StatelessWidget {
  const MaterialPickerCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.hint,
    required this.fileName,
    required this.isSelected,
    required this.onTap,
    this.leading,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String hint;
  final String? fileName;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
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
                        _DefaultPickerIcon(icon: icon, iconColor: iconColor),
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
}

class _DefaultPickerIcon extends StatelessWidget {
  const _DefaultPickerIcon({required this.icon, required this.iconColor});

  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, color: iconColor, size: 24),
    );
  }
}

class FaceImageThumbnail extends StatelessWidget {
  const FaceImageThumbnail({super.key, required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
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
}

class SourceVideoThumbnail extends StatelessWidget {
  const SourceVideoThumbnail({super.key, required this.videoPath});

  final String videoPath;

  @override
  Widget build(BuildContext context) {
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
}
