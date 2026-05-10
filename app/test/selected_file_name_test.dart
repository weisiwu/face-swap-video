import 'package:flutter_test/flutter_test.dart';
import 'package:face_swap_video/utils/selected_file_name.dart';

void main() {
  group('selectedFileName', () {
    test('uses placeholder when no file is selected', () {
      expect(selectedFileName(null), unselectedFileNameLabel);
      expect(selectedFileName(''), unselectedFileNameLabel);
    });

    test('returns the final path segment for selected Android files', () {
      expect(
        selectedFileName('/storage/emulated/0/Movies/source.mp4'),
        'source.mp4',
      );
      expect(
        selectedFileName('/storage/emulated/0/Pictures/face.jpg'),
        'face.jpg',
      );
    });
  });
}
