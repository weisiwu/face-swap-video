import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// 照片网格选择器
/// 直接获取设备相册权限，以 3 列网格展示照片，单选一张后返回路径
class PhotoGridScreen extends StatefulWidget {
  const PhotoGridScreen({super.key});

  @override
  State<PhotoGridScreen> createState() => _PhotoGridScreenState();
}

class _PhotoGridScreenState extends State<PhotoGridScreen> {
  List<AssetEntity> _photos = [];
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

    // isAuth 或 hasAccess 都视为有权限（兼容 Android 13+ 的 limited access）
    if (perm.isAuth || perm.hasAccess) {
      setState(() {
        _hasPermission = true;
        _permissionError = null;
      });
      await _loadPhotos();
    } else {
      setState(() {
        _hasPermission = false;
        _loading = false;
        _permissionError = perm == PermissionState.denied
            ? '相册权限被拒绝'
            : '需要相册访问权限才能选择照片';
      });
    }
  }

  Future<void> _loadPhotos() async {
    // 获取最近相册
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    // 加载最近 200 张照片
    final album = albums.first;
    final count = await album.assetCountAsync;
    final loadCount = count > 200 ? 200 : count;

    final assets = await album.getAssetListRange(
      start: 0,
      end: loadCount,
    );

    if (mounted) {
      setState(() {
        _photos = assets;
        _loading = false;
      });
    }
  }

  Future<void> _onPhotoTap(AssetEntity asset) async {
    // 获取原文件路径
    final file = await asset.file;
    if (file != null && mounted) {
      Navigator.of(context).pop(file.path);
    }
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
              // 顶栏
              _buildTopBar(),
              // 内容区
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
          const Text(
            '选择人脸照片',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (_photos.isNotEmpty)
            Text(
              '${_photos.length} 张',
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
        child: CircularProgressIndicator(
          color: Color(0xFFEC4899),
        ),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    if (_photos.isEmpty) {
      return Center(
        child: Text(
          '没有找到照片',
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
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        return _buildPhotoTile(_photos[index]);
      },
    );
  }

  Widget _buildPhotoTile(AssetEntity asset) {
    return GestureDetector(
      onTap: () => _onPhotoTap(asset),
      child: FutureBuilder<Uint8List?>(
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
          return Container(
            color: Colors.white.withValues(alpha: 0.03),
          );
        },
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
              Icons.photo_library_outlined,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
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
