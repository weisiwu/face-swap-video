import 'package:flutter_test/flutter_test.dart';
import 'package:face_swap_video/features/media/utils/album_display_name.dart';

void main() {
  group('displayAlbumName', () {
    test('uses friendly labels for common albums', () {
      expect(displayAlbumName(''), '最近项目');
      expect(displayAlbumName('  Recent  '), '最近项目');
      expect(displayAlbumName('download'), '下载 / Download');
    });

    test('keeps custom album names unchanged except trimming whitespace', () {
      expect(displayAlbumName('  Camera  '), 'Camera');
      expect(displayAlbumName('Screenshots'), 'Screenshots');
    });

    test('labels video folders only when requested', () {
      expect(displayAlbumName('Movies'), 'Movies');
      expect(
        displayAlbumName('Movies', includeVideoFolders: true),
        '视频 / Movies',
      );
    });
  });
}
