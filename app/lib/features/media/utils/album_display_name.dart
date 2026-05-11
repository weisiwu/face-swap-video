String displayAlbumName(String rawName, {bool includeVideoFolders = false}) {
  final name = rawName.trim();
  final normalizedName = name.toLowerCase();

  if (name.isEmpty || normalizedName == 'recent') {
    return '最近项目';
  }
  if (normalizedName == 'download') {
    return '下载 / Download';
  }
  if (includeVideoFolders && normalizedName == 'movies') {
    return '视频 / Movies';
  }
  return name;
}
