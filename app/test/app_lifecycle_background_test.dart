import 'package:face_swap_video/utils/app_lifecycle_background.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isBackgroundLifecycleState', () {
    test('treats paused detached and hidden as background states', () {
      expect(isBackgroundLifecycleState(AppLifecycleState.paused), isTrue);
      expect(isBackgroundLifecycleState(AppLifecycleState.detached), isTrue);
      expect(isBackgroundLifecycleState(AppLifecycleState.hidden), isTrue);
    });

    test('keeps resumed and inactive in the foreground bucket', () {
      expect(isBackgroundLifecycleState(AppLifecycleState.resumed), isFalse);
      expect(isBackgroundLifecycleState(AppLifecycleState.inactive), isFalse);
    });
  });
}
