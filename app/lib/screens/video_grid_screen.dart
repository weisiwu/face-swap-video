import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

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
    final perm = await PhotoManager.requestPermissionExtend();
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

    final selected = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: const Color(0xFF15111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Row(
                  children: [
                    Icon(Icons.folder_rounded, color: Color(0xFF3B82F6)),
                    SizedBox(width: 10),
                    Text(
                      '切换视频文件夹',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _albums.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  itemBuilder: (context, index) {
                    final album = _albums[index];
                    final isSelected = album.id == _selectedAlbum?.id;
                    return FutureBuilder<int>(
                      future: album.assetCountAsync,
                      builder: (context, snapshot) {
                        final count = snapshot.data;
                        return ListTile(
                          leading: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.folder_outlined,
                            color: isSelected
                                ? const Color(0xFF3B82F6)
                                : Colors.white.withValues(alpha: 0.55),
                          ),
                          title: Text(
                            _albumDisplayName(album),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: count == null
                              ? null
                              : Text(
                                  '$count 个视频',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                          onTap: () => Navigator.of(context).pop(album),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await _selectAlbum(selected);
    }
  }

  String _albumDisplayName(AssetPathEntity album) {
    final name = album.name.trim();
    if (name.isEmpty || name.toLowerCase() == 'recent') {
      return '最近项目';
    }
    if (name.toLowerCase() == 'download') {
      return '下载 / Download';
    }
    if (name.toLowerCase() == 'movies') {
      return '视频 / Movies';
    }
    return name;
  }

  Future<void> _onVideoTap(AssetEntity asset) async {
    final file = await asset.file;
    if (file != null && mounted) {
      Navigator.of(context).pop(file.path);
    }
  }

  Future<void> _pickVideoFromFileManager() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty && mounted) {
      Navigator.of(context).pop(path);
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
          child: const Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 20,
                color: Color(0xFF60A5FA),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '从文件管理选择视频',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
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
        : _albumDisplayName(_selectedAlbum!);

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
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
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
            Icon(
              Icons.video_library_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 20),
            Text(
              _permissionError ?? '需要相册访问权限',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              '请在系统设置中授予相册访问权限',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: _requestAndLoad,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
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
                    color: Colors.white,
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
