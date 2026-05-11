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

  group('API error messages', () {
    test('explains when FaceFusion cannot detect the source face', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      unawaited(
        server.first.then((request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/api/swap/status/job-no-face');
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'job_id': 'job-no-face',
                'status': 'failed',
                'error':
                    'Video face swap failed: [FACEFUSION.CORE] no source face detected!',
              }),
            );
          await request.response.close();
        }),
      );

      final service = ApiService(
        baseUrl: 'http://${server.address.host}:${server.port}',
      );

      addTearDown(() async {
        await server.close(force: true);
      });

      expect(
        () => service.pollSwapJob(jobId: 'job-no-face'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            '没有检测到人脸，请换一张清晰正脸照后重试',
          ),
        ),
      );
    });

    test(
      'returns user friendly message when starting video job fails',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final source = await File(
          '${Directory.systemTemp.path}/source_face_error_test.jpg',
        ).writeAsBytes([1, 2, 3]);
        final target = await File(
          '${Directory.systemTemp.path}/target_video_error_test.mp4',
        ).writeAsBytes([4, 5, 6, 7]);

        unawaited(
          server.first.then((request) async {
            await request.drain<void>();
            request.response
              ..statusCode = 500
              ..write('model crashed');
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

        expect(
          () => service.swapVideoJob(
            sourcePath: source.path,
            targetPath: target.path,
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              '处理接口返回异常，请稍后重试',
            ),
          ),
        );
      },
    );
  });
}
