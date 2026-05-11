import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:face_swap_video/features/generation/services/api_service.dart';
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

  group('multipart upload', () {
    test(
      'sends multipart content type with boundary for video job uploads',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final source = await File(
          '${Directory.systemTemp.path}/source_face_test.jpg',
        ).writeAsBytes([1, 2, 3]);
        final target = await File(
          '${Directory.systemTemp.path}/target_video_test.mp4',
        ).writeAsBytes([4, 5, 6, 7]);

        unawaited(
          server.first.then((request) async {
            expect(request.method, 'POST');
            expect(request.uri.path, '/api/swap/video/job');
            expect(
              request.headers.contentType?.mimeType,
              'multipart/form-data',
            );
            expect(
              request.headers.contentType?.parameters['boundary'],
              isNot(isEmpty),
            );
            await request.drain<void>();
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'job_id': 'job-1', 'status': 'queued'}));
            await request.response.close();
          }),
        );

        final service = ApiService(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );

        addTearDown(() async {
          await server.close(force: true);
          if (await source.exists()) await source.delete();
          if (await target.exists()) await target.delete();
        });

        final jobId = await service.swapVideoJob(
          sourcePath: source.path,
          targetPath: target.path,
        );

        expect(jobId, 'job-1');
      },
    );
  });
}
