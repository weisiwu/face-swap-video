import 'package:face_swap_video/features/generation/utils/job_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveJobProgress', () {
    test(
      'uses positive server supplied progress when status payload includes progress',
      () {
        expect(
          resolveJobProgress({
            'status': 'queued',
            'progress': 0.05,
          }, pollCount: 1),
          0.05,
        );
        expect(
          resolveJobProgress({
            'status': 'processing',
            'progress': 63,
          }, pollCount: 2),
          0.63,
        );
        expect(
          resolveJobProgress({
            'status': 'processing',
            'percent': '78',
          }, pollCount: 3),
          0.78,
        );
      },
    );

    test(
      'falls back to synthetic movement when server reports zero progress',
      () {
        final first = resolveJobProgress({
          'status': 'processing',
          'progress': 0,
        }, pollCount: 1);
        final second = resolveJobProgress({
          'status': 'processing',
          'progress': 0,
        }, pollCount: 2);

        expect(first, greaterThan(0));
        expect(second, greaterThan(first));
      },
    );

    test(
      'keeps visible forward movement when server only reports processing status',
      () {
        final first = resolveJobProgress({'status': 'queued'}, pollCount: 1);
        final second = resolveJobProgress({
          'status': 'processing',
        }, pollCount: 2);
        final third = resolveJobProgress({
          'status': 'processing',
        }, pollCount: 3);

        expect(first, greaterThan(0));
        expect(second, greaterThan(first));
        expect(third, greaterThan(second));
        expect(third, lessThan(0.95));
      },
    );

    test('completed status resolves near result download phase', () {
      expect(resolveJobProgress({'status': 'completed'}, pollCount: 10), 0.95);
    });
  });
}
