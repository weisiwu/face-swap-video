double resolveJobProgress(
  Map<String, dynamic> payload, {
  required int pollCount,
}) {
  final status = payload['status']?.toString();
  if (status == 'completed') return 0.95;

  final serverProgress = _readServerProgress(payload);
  if (serverProgress != null && serverProgress > 0) {
    return serverProgress.clamp(0.0, 0.94).toDouble();
  }

  if (status == 'queued' || status == 'processing' || status == null) {
    final safePollCount = pollCount < 1 ? 1 : pollCount;
    return (0.12 + safePollCount * 0.055).clamp(0.12, 0.9).toDouble();
  }

  return 0.35;
}

double? _readServerProgress(Map<String, dynamic> payload) {
  for (final key in const ['progress', 'percent', 'percentage']) {
    final rawValue = payload[key];
    final progress = _parseProgressValue(rawValue);
    if (progress != null) return progress;
  }
  return null;
}

double? _parseProgressValue(Object? value) {
  if (value == null) return null;
  final numericValue = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (numericValue == null || numericValue.isNaN || numericValue.isInfinite) {
    return null;
  }
  if (numericValue > 1) return numericValue / 100;
  return numericValue;
}
