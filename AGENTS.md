# Codex instructions — face-swap-video

## Highest-priority workflow

For any change in this repository, follow the `context-aware-dev` workflow before editing files.

Codex-compatible interpretation of that workflow:

1. Read the project context files first:
   - `context/project-context.md`
   - `context/crag-supplemental-context.md`
2. Use `workflow-crag-starter` / CRAG to locate relevant files and impact scope instead of guessing paths.
3. Then inspect the concrete source/test/doc files and make the smallest safe change.
4. Run the minimum relevant verification before finishing.

## CRAG query command

```bash
cd /tmp/zfj/apps/workflow-crag-starter
python3 - <<'PY'
from workflow_crag.cli import main
import sys
sys.argv = [
    'workflow-crag-starter',
    'query',
    '/tmp/zfj/apps/face-swap-video',
    'replace with task keywords',
    '--crag-dir',
    '/tmp/zfj/apps/face-swap-video_CRAG',
    '--k',
    '8',
    '--backend',
    'hash',
]
main()
PY
```

Refresh the index when key context/docs/source files changed or query freshness reports stale:

```bash
cd /tmp/zfj/apps/workflow-crag-starter
python3 -m workflow_crag.setup_crag /tmp/zfj/apps/face-swap-video --backend hash
```

Do not use `--with-ai` unless AI provider credentials are configured.

## Project rules

- This is a Flutter Android App. Do not replace Android validation with Web/macOS validation.
- Build from the ASCII path: `/tmp/zfj/apps/face-swap-video/app`.
- Background conversion semantics: clicking generate starts normal foreground conversion; only after the app is moved to background should background waiting/notification semantics apply.
- FaceFusion API base URL: `https://facefusion.baoganai.com`.
- Current API paths: `/api/health`, `/api/swap/image`, `/api/swap/video/job`, `/api/swap/status/{jobId}`, `/api/swap/result/{jobId}`.
- Version is shown in the app footer; minor for features, patch for bug fixes.
- Do not update dashboard/docs site or project overview unless explicitly requested.

## Verification

Default minimum checks for app changes:

```bash
cd /tmp/zfj/apps/face-swap-video/app
dart format lib test
flutter analyze
flutter test
```

Android screenshot helper:

```bash
cd /tmp/zfj/apps/face-swap-video
python3 scripts/screenshot-android.py
```

Release APK build:

```bash
cd /tmp/zfj/apps/face-swap-video
scripts/build-release-apks.sh
```
