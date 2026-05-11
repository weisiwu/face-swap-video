import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:face_swap_video/features/media/utils/album_display_name.dart';

Future<AssetPathEntity?> showMediaAlbumPicker({
  required BuildContext context,
  required List<AssetPathEntity> albums,
  required AssetPathEntity? selectedAlbum,
  required String title,
  required String countLabel,
  required Color accentColor,
  bool includeVideoFolders = false,
}) {
  return showModalBottomSheet<AssetPathEntity>(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded, color: accentColor),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
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
                itemCount: albums.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                itemBuilder: (context, index) {
                  final album = albums[index];
                  final isSelected = album.id == selectedAlbum?.id;
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
                              ? accentColor
                              : Colors.white.withValues(alpha: 0.55),
                        ),
                        title: Text(
                          displayAlbumName(
                            album.name,
                            includeVideoFolders: includeVideoFolders,
                          ),
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
                                '$count 个$countLabel',
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
}
