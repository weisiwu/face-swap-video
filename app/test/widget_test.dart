import 'package:face_swap_video/main.dart';
import 'package:face_swap_video/providers/generation_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('App renders generation screen after splash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => GenerationProvider(),
        child: const FaceSwapApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 3000));

    expect(find.text('视频换脸'), findsOneWidget);
    expect(find.text('源视频'), findsOneWidget);
  });
}
