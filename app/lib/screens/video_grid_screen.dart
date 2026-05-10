import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// 视频网格选择器
/// 与 PhotoGridScreen 同架构，筛选视频、3 列网格、单选返回路径
class VideoGridScreen extends StatefulWidget {
  const VideoGridScreen({super.key});

  @override
  State<VideoGridScreen> createState() => _VideoGridScreenState();
}

class _VideoGridScreenState extends State<VideoGridScreen> {
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
    final perm = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;

    // isAuth 或 hasAccess 都视为有权限（兼容 Android 13+ limited access）
    if (perm.isAuth || perm.hasAccess) {
      setState(() {
        _hasPermission = true;
        _permissionError = null;
      });
      await _loadVideos();
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

  Future<void> _loadVideos() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      onlyAll: false, // 获取所有相册，包括 Movies 等
    );

    if (albums.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // 合并所有相册的视频
    final allVideos = <AssetEntity>[];
    for (final album in albums) {
      final count = await album.assetCountAsync;
      if (count > 0) {
        final loadCount = count > 50 ? 50 : count;
        final assets = await album.getAssetListRange(start: 0, end: loadCount);
        allVideos.addAll(assets);
      }
    }

    if (mounted) {
      setState(() {
        _videos = allVideos;
        _loading = false;
      });
    }
  }

  Future<void> _onVideoTap(AssetEntity asset) async {
    final file = await asset.file;
    if (file != null && mounted) {
      Navigator.of(context).pop(file.path);
    }
  }

  // 格式化时长
  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

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
          child: Column(
            children: [
              _buildTopBar(),
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
          const Icon(Icons.videocam_rounded, color: Color(0xFF3B82F6), size: 20),
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
          '没有找到视频',
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
        return _buildVideoTile(_videos[index]);
      },
    );
  }

  Widget _buildVideoTile(AssetEntity asset) {
    return GestureDetector(
      onTap: () => _onVideoTap(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 缩略图
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize(300, 300),
              format: ThumbnailFormat.jpeg,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              }
              return Container(color: Colors.white.withValues(alpha: 0.03));
            },
          ),
          // 时长标签
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(asset.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // 播放图标
          Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined,
                size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 20),
            Text(
              _permissionError ?? '需要相册访问权限',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              '请在系统设置中授予相册访问权限',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.4)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: _requestAndLoad,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '重新授权',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
