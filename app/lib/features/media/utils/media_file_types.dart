const Set<String> _videoFileExtensions = {'.mp4', '.mov', '.avi', '.mkv'};

bool isVideoFilePath(String path) {
  final normalizedPath = path.toLowerCase();
  return _videoFileExtensions.any(normalizedPath.endsWith);
}
