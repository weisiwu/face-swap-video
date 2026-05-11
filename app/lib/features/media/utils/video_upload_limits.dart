const Duration maxVideoUploadDuration = Duration(minutes: 1);
const int maxVideoUploadBytes = 100 * 1024 * 1024;

class VideoUploadValidationResult {
  const VideoUploadValidationResult._({this.errorMessage});

  const VideoUploadValidationResult.valid() : this._();

  const VideoUploadValidationResult.invalid(String message)
    : this._(errorMessage: message);

  final String? errorMessage;

  bool get isValid => errorMessage == null;
}

VideoUploadValidationResult validateVideoUploadLimits({
  Duration? duration,
  int? sizeBytes,
}) {
  if (duration != null && duration > maxVideoUploadDuration) {
    return const VideoUploadValidationResult.invalid('视频长度不能超过1分钟，请重新选择');
  }

  if (sizeBytes != null && sizeBytes > maxVideoUploadBytes) {
    return const VideoUploadValidationResult.invalid('视频文件不能超过100 MB，请压缩后重新选择');
  }

  return const VideoUploadValidationResult.valid();
}

String formatVideoUploadLimitHint() => '视频限制：不超过1分钟，文件不超过100 MB';
