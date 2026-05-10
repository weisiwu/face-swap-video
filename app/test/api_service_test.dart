import 'package:face_swap_video/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiService URL configuration', () {
    test('uses the production tunnel URL by default', () {
      final service = ApiService();

      expect(service.baseUrl, 'https://facefusion.baoganai.com');
    });

    test('trims trailing slash when updating the base URL', () {
      final service = ApiService(baseUrl: 'https://example.test/');

      service.setBaseUrl('https://api.example.test/');

      expect(service.baseUrl, 'https://api.example.test');
    });
  });
}
