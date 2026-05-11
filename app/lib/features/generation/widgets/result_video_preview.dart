import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:face_swap_video/core/services/app_logger.dart';

const String _logTag = 'ResultVideoPreview';

class ResultVideoPreview extends StatefulWidget {
  const ResultVideoPreview({super.key, required this.resultPath});

  final String resultPath;

  @override
  State<ResultVideoPreview> createState() => _ResultVideoPreviewState();
}

class _ResultVideoPreviewState extends State<ResultVideoPreview> {
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
    appLogger.i(_logTag, 'initialize path=${widget.resultPath}');
    try {
      await _controller.initialize();
      await _controller.setLooping(false);
      final value = _controller.value;
      appLogger.i(
        _logTag,
        'initialize done size=${value.size.width.toInt()}x${value.size.height.toInt()} durationMs=${value.duration.inMilliseconds}',
      );
      if (mounted) {
        setState(() => _initializing = false);
      }
    } catch (error, stack) {
      appLogger.e(
        _logTag,
        'initialize failed path=${widget.resultPath}',
        error,
        stack,
      );
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
