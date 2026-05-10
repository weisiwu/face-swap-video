import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../utils/album_display_name.dart';

/// 照片网格选择器
/// 直接获取设备相册权限，以 3 列网格展示照片，支持切换相册/文件夹，单选一张后返回路径
class PhotoGridScreen extends StatefulWidget {
  const PhotoGridScreen({super.key});

  @override
  State<PhotoGridScreen> createState() => _PhotoGridScreenState();
}

class _PhotoGridScreenState extends State<PhotoGridScreen> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
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
      await _loadAlbumsAndPhotos();
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

  Future<void> _loadAlbumsAndPhotos() async {
    setState(() => _loading = true);

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
    );

    if (!mounted) return;

    _albums = albums;
    if (_selectedAlbum == null && albums.isNotEmpty) {
      _selectedAlbum = albums.first;
    } else if (_selectedAlbum != null) {
      _selectedAlbum = _findAlbumById(albums, _selectedAlbum!.id);
      _selectedAlbum ??= albums.isNotEmpty ? albums.first : null;
    }

    await _loadPhotosFromSelectedAlbum();
  }

  AssetPathEntity? _findAlbumById(List<AssetPathEntity> albums, String id) {
    for (final album in albums) {
      if (album.id == id) return album;
    }
    return null;
  }

  Future<void> _loadPhotosFromSelectedAlbum() async {
    final album = _selectedAlbum;
    if (album == null) {
      if (mounted) {
        setState(() {
          _photos = [];
          _loading = false;
        });
      }
      return;
    }

    final count = await album.assetCountAsync;
    final loadCount = count > 300 ? 300 : count;
    final assets = await album.getAssetListRange(start: 0, end: loadCount);

    if (mounted) {
      setState(() {
        _photos = assets;
        _loading = false;
      });
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    if (_selectedAlbum?.id == album.id) return;

    setState(() {
      _selectedAlbum = album;
      _photos = [];
      _loading = true;
    });
    await _loadPhotosFromSelectedAlbum();
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
                    Icon(Icons.folder_rounded, color: Color(0xFFEC4899)),
                    SizedBox(width: 10),
                    Text(
                      '切换照片文件夹',
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
                                ? const Color(0xFFEC4899)
                                : Colors.white.withValues(alpha: 0.55),
                          ),
                          title: Text(
                            displayAlbumName(album.name),
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
                                  '$count 张照片',
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

  Future<void> _onPhotoTap(AssetEntity asset) async {
    // 获取原文件路径
    final file = await asset.file;
    if (file != null && mounted) {
      Navigator.of(context).pop(file.path);
    }
  }

  Future<void> _pickPhotoFromFileManager() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty && mounted) {
      Navigator.of(context).pop(path);
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

  Widget _buildFileManagerButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        onTap: _pickPhotoFromFileManager,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEC4899).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFEC4899).withValues(alpha: 0.28),
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 20,
                color: Color(0xFFF472B6),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '从文件管理选择照片',
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
                color: Color(0xFFF472B6),
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
        : displayAlbumName(_selectedAlbum!.name);

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
                color: Color(0xFFEC4899),
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
        child: CircularProgressIndicator(color: Color(0xFFEC4899)),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    if (_photos.isEmpty) {
      return Center(
        child: Text(
          '当前文件夹没有照片',
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
          return Container(color: Colors.white.withValues(alpha: 0.03));
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
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
