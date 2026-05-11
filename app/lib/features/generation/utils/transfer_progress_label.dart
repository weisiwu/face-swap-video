const String uploadMaterialBaseLabel = '上传素材中...';

String formatTransferBytes(int bytes) {
  final safeBytes = bytes < 0 ? 0 : bytes;
  const kb = 1024;
  const mb = 1024 * 1024;

  if (safeBytes < mb) {
    final roundedKb = (safeBytes / kb).ceil().clamp(1, 999);
    return '$roundedKb KB';
  }

  final value = safeBytes / mb;
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0')
      ? '${fixed.substring(0, fixed.length - 2)} MB'
      : '$fixed MB';
}

String formatUploadProgressLabel({
  required int uploadedBytes,
  required int totalBytes,
}) {
  if (totalBytes <= 0) return uploadMaterialBaseLabel;

  final clampedUploaded = uploadedBytes.clamp(0, totalBytes);
  return '$uploadMaterialBaseLabel（${formatTransferBytes(clampedUploaded)} / ${formatTransferBytes(totalBytes)}）';
}
