const String unselectedFileNameLabel = '未选择';

String selectedFileName(String? path) {
  if (path == null || path.isEmpty) {
    return unselectedFileNameLabel;
  }
  return path.split('/').last;
}
