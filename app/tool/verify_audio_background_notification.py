#!/usr/bin/env python3
from pathlib import Path

app_root = Path(__file__).resolve().parents[1]
project_root = app_root.parent
server = (project_root / 'server/api/server.py').read_text()
api = (app_root / 'lib/services/api_service.dart').read_text()
provider = (app_root / 'lib/providers/generation_provider.dart').read_text()
main = (app_root / 'lib/main.dart').read_text()
pubspec = (app_root / 'pubspec.yaml').read_text()
manifest = (app_root / 'android/app/src/main/AndroidManifest.xml').read_text()

checks = [
    ('server async video job endpoint', '@app.post("/api/swap/video/job")' in server and 'threading.Thread' in server),
    ('server real job status endpoint', '@app.get("/api/swap/status/{job_id}")' in server and 'JOBS' in server and 'status": "completed"' not in server),
    ('server result download endpoint', '@app.get("/api/swap/result/{job_id}")' in server and 'FileResponse' in server),
    ('server exposes ffmpeg path to FaceFusion', 'FFMPEG_SEARCH_PATHS' in server and 'os.environ["PATH"]' in server),
    ('server copies original audio back', '_copy_audio_from_target' in server and '-map' in server and '0:v:0' in server and '1:a?' in server),
    ('client uploads video as background server job', 'swapVideoJob' in api and '/api/swap/video/job' in api),
    ('client polls server job after upload', 'pollSwapJob' in api and '/api/swap/status/' in api and '/api/swap/result/' in api),
    ('provider uses async video job path', '_api.swapVideoJob' in provider and '_api.pollSwapJob' in provider),
    ('local notification dependency', 'flutter_local_notifications:' in pubspec),
    ('android notification permission', 'android.permission.POST_NOTIFICATIONS' in manifest),
    ('notification service initialized', 'NotificationService.initialize' in main),
    ('completion notification sent', 'NotificationService.showGenerationCompleted' in provider),
    ('failure notification sent', 'NotificationService.showGenerationFailed' in provider),
]

failed = [name for name, ok in checks if not ok]
if failed:
    print('FAILED checks:')
    for name in failed:
        print(f'- {name}')
    raise SystemExit(1)
print('All audio/background notification checks passed.')
