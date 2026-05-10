import 'package:flutter_test/flutter_test.dart';
import 'package:face_swap_video/main.dart';

void main() {
  testWidgets('App renders generation screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceSwapApp());
    expect(find.text('视频换脸'), findsOneWidget);
    expect(find.text('开始换脸'), findsOneWidget);
  });
}
