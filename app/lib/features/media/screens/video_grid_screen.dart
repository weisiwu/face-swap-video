import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:face_swap_video/core/services/app_logger.dart';
import 'package:face_swap_video/features/media/utils/album_display_name.dart';
import 'package:face_swap_video/features/media/utils/video_upload_limits.dart';
import 'package:face_swap_video/features/media/widgets/media_album_picker_sheet.dart';
import 'package:face_swap_video/features/media/widgets/media_permission_denied.dart';
import 'package:face_swap_video/features/media/widgets/video_tile.dart';

const String _logTag = 'VideoGrid';

/// 视频网格选择器
/// 与 PhotoGridScreen 同架构，筛选视频、支持切换相册/文件夹、3 列网格、单选返回路径
class VideoGridScreen extends StatefulWidget {
  const VideoGridScreen({super.key});

  @override
  State<VideoGridScreen> createState() => _VideoGridScreenState();
}

class _VideoGridScreenState extends State<VideoGridScreen> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _videos = [];
  bool _loading = true;
  bool _hasPermission = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _requestAndLoad();
  }

  Future<void> _requestAndLoad() async {
    appLogger.i(_logTag, 'requestPermission start');
    final perm = await PhotoManager.requestPermissionExtend();
    appLogger.i(
      _logTag,
      'requestPermission result=$perm isAuth=${perm.isAuth} hasAccess=${perm.hasAccess}',
    );
    if (!mounted) return;

    // isAuth 或 hasAccess 都视为有权限（兼容 Android 13+ limited access）
    if (perm.isAuth || perm.hasAccess) {
      setState(() {
        _hasPermission = true;
        _permissionError = null;
      });
      await _loadAlbumsAndVideos();
    } else {
      setState(() {
        _hasPermission = false;
        _loading = false;
        _permissionError = perm == PermissionState.denied
            ? '相册权限被拒绝'
            : '需要相册访问权限才能选择视频';
      });
    }
  }

  Future<void> _loadAlbumsAndVideos() async {
    setState(() => _loading = true);

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      onlyAll: false, // 获取所有相册，包括 Movies / Download 等
    );
    appLogger.i(_logTag, 'loadAlbums count=${albums.length}');

    if (!mounted) return;

    _albums = albums;
    if (_selectedAlbum == null && albums.isNotEmpty) {
      _selectedAlbum = albums.first;
    } else if (_selectedAlbum != null) {
      _selectedAlbum = _findAlbumById(albums, _selectedAlbum!.id);
      _selectedAlbum ??= albums.isNotEmpty ? albums.first : null;
    }

    await _loadVideosFromSelectedAlbum();
  }

  AssetPathEntity? _findAlbumById(List<AssetPathEntity> albums, String id) {
    for (final album in albums) {
      if (album.id == id) return album;
    }
    return null;
  }

  Future<void> _loadVideosFromSelectedAlbum() async {
    final album = _selectedAlbum;
    if (album == null) {
      if (mounted) {
        setState(() {
          _videos = [];
          _loading = false;
        });
      }
      return;
    }

    final count = await album.assetCountAsync;
    final loadCount = count > 200 ? 200 : count;
    final assets = await album.getAssetListRange(start: 0, end: loadCount);

    if (mounted) {
      setState(() {
        _videos = assets;
        _loading = false;
      });
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    if (_selectedAlbum?.id == album.id) return;

    setState(() {
      _selectedAlbum = album;
      _videos = [];
      _loading = true;
    });
    await _loadVideosFromSelectedAlbum();
  }

  Future<void> _showAlbumPicker() async {
    if (_albums.isEmpty) return;

    final selected = await showMediaAlbumPicker(
      context: context,
      albums: _albums,
      selectedAlbum: _selectedAlbum,
      title: '切换视频文件夹',
      countLabel: '视频',
      accentColor: const Color(0xFF3B82F6),
      includeVideoFolders: true,
    );

    if (selected != null) {
      await _selectAlbum(selected);
    }
  }

  Future<void> _onVideoTap(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null || !mounted) {
      if (file == null) {
        appLogger.w(
          _logTag,
          'video asset returned null file assetId=${asset.id}',
        );
      }
      return;
    }

    final validation = await _validateSelectedVideo(
      file.path,
      duration: Duration(seconds: asset.duration),
    );
    if (!mounted) return;
    if (!validation.isValid) {
      appLogger.w(
        _logTag,
        'video rejected by limits path=${file.path} reason=${validation.errorMessage}',
      );
      _showVideoLimitMessage(validation.errorMessage!);
      return;
    }

    appLogger.i(
      _logTag,
      'select video from album path=${file.path} durationSec=${asset.duration}',
    );
    Navigator.of(context).pop(file.path);
  }

  Future<void> _pickVideoFromFileManager() async {
    appLogger.i(_logTag, 'pickVideoFromFileManager open');
    final result = await FilePicker.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty || !mounted) {
      appLogger.i(_logTag, 'pickVideoFromFileManager cancelled');
      return;
    }

    final validation = await _validateSelectedVideo(path);
    if (!mounted) return;
    if (!validation.isValid) {
      appLogger.w(
        _logTag,
        'video rejected by limits path=$path reason=${validation.errorMessage}',
      );
      _showVideoLimitMessage(validation.errorMessage!);
      return;
    }

    appLogger.i(_logTag, 'pickVideoFromFileManager selected path=$path');
    Navigator.of(context).pop(path);
  }

  Future<VideoUploadValidationResult> _validateSelectedVideo(
    String path, {
    Duration? duration,
  }) async {
    final file = File(path);
    final sizeBytes = await file.exists() ? await file.length() : null;
    final resolvedDuration = duration ?? await _readVideoDuration(path);
    return validateVideoUploadLimits(
      duration: resolvedDuration,
      sizeBytes: sizeBytes,
    );
  }

  Future<Duration?> _readVideoDuration(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return controller.value.duration;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  void _showVideoLimitMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$message\n${formatVideoUploadLimitHint()}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0A1A), Color(0xFF1A0F2E), Color(0xFF0D1117)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              _buildFileManagerButton(),
              _buildAlbumBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: Colors.white.withValues(alpha: 0.6),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Icon(
            Icons.videocam_rounded,
            color: Color(0xFF3B82F6),
            size: 20,
          ),
          const SizedBox(width: 8),
          const Text(
            '选择视频',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (_videos.isNotEmpty)
            Text(
              '${_videos.length} 个',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildFileManagerButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        onTap: _pickVideoFromFileManager,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.folder_open_rounded,
                size: 20,
                color: Color(0xFF60A5FA),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '从文件管理选择视频',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatVideoUploadLimitHint(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.52),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFF60A5FA),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumBar() {
    if (!_hasPermission || _albums.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedName = _selectedAlbum == null
        ? '选择文件夹'
        : displayAlbumName(_selectedAlbum!.name, includeVideoFolders: true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        onTap: _showAlbumPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.folder_rounded,
                size: 20,
                color: Color(0xFF3B82F6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selectedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '切换',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    if (_videos.isEmpty) {
      return Center(
        child: Text(
          '当前文件夹没有视频',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        return VideoTile(asset: video, onTap: () => _onVideoTap(video));
      },
    );
  }

  Widget _buildPermissionDenied() {
    return MediaPermissionDenied(
      icon: Icons.video_library_outlined,
      message: _permissionError ?? '需要相册访问权限',
      gradientColors: const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
      onRetry: _requestAndLoad,
    );
  }
}
