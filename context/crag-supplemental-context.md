# CRAG 补充上下文：face-swap-video

> 来源：使用 `workflow-crag-starter` 对当前项目生成 Hash CRAG 索引后整理。
> 生成命令：`cd /tmp/zfj/apps/workflow-crag-starter && python3 -m workflow_crag.setup_crag /tmp/zfj/apps/face-swap-video --backend hash`
> CRAG Sidecar：`/tmp/zfj/apps/face-swap-video_CRAG`（真实路径会解析到 `~/Desktop/致富经/apps/face-swap-video_CRAG`）

## 1. CRAG 索引状态

- 后端：`hash`
- 代码块：1481
- 文档块：132
- 依赖块：3
- `workflow-crag-starter` 会生成 `.mcp.json` 与 `.claude/settings.local.json` agent 适配文件；本次未纳入提交，因为文件包含本机绝对路径，避免污染仓库。
- 注意：`python3 -m workflow_crag.cli ...` 目前不会实际执行 CLI；如需查询，用 `python3 - <<'PY'` 导入 `workflow_crag.cli.main()` 或使用已安装的 console script。

## 2. Agent 指令入口兼容

同一套上下文感知开发流程同时提供给不同 Agent：

- Hermes：优先加载 skill `context-aware-dev`，并读取 `HERMES.md`。
- Codex：读取仓库根目录 `AGENTS.md`。
- 通用上下文：读取 `context/project-context.md` 与本文件。

如果修改其中任一入口，必须保持 `AGENTS.md`、`HERMES.md`、`context-aware-dev` skill 与本文件语义一致。

## 3. 修改前必读顺序

1. `context/project-context.md`：项目铁律、阶段、Android/构建约束。
2. 本文件：CRAG 生成的补充索引与模块责任。
3. 针对任务使用 CRAG 查询定位相关文件，而不是直接猜文件。
4. 读取具体源码/测试后再改动。

## 4. 高优先级项目铁律

- 这是 **Flutter Android App**；开发、构建、截图优先使用 Android 端验证。
- 含中文路径导致 Gradle/Java 易异常，构建必须走 `/tmp/zfj/apps/face-swap-video/app`。
- 后台转换规则：点击转换时仍是前台正常转换；只有 App 被切到后台后，才进入后台等待/后台通知语义。
- API 协议已固化：`/api/health`、`/api/swap/image`、`/api/swap/video/job`、`/api/swap/status/{jobId}`、`/api/swap/result/{jobId}`。
- 版本号展示在生成页底部；功能升级 minor，Bug 修复升级 patch。

## 5. 关键 LOC 索引

| LOC-ID | Path | Size | Responsibility | 改动风险 |
|---|---|---:|---|---|
| LOC-ENT-001 | `app/lib/main.dart` | S | 初始化 Flutter、通知服务、Provider 注入、Splash 到 AuthGate 切换、监听生命周期 | 生命周期改动会影响后台转换状态 |
| LOC-CORE-001 | `app/lib/features/generation/providers/generation_provider.dart` | M | 生成流程状态机：素材选择、健康检查、压缩、上传进度、视频任务轮询、取消/失败/完成 | 最核心高风险；必须覆盖状态流与前后台切换 |
| LOC-API-001 | `app/lib/features/generation/services/api_service.dart` | M | FaceFusion HTTP API：健康检查、图片同步换脸、视频 job 创建/轮询/下载、上传进度追踪 | 服务端协议变化必须同步测试与文档 |
| LOC-UI-001 | `app/lib/features/generation/screens/generation_screen.dart` | L | 主生成页：素材入口、登录拦截、进度/错误/完成弹框、退出确认、版本展示 | 弹框 Navigator 竞态与登录返回流程需重点验证 |
| LOC-UI-002 | `app/lib/features/generation/widgets/generation_progress_dialog.dart` | S | 处理中弹框与取消/退出入口 | 取消行为不能遗留后台任务状态 |
| LOC-UI-003 | `app/lib/features/generation/widgets/result_preview_dialog.dart` | S | 结果预览、保存到相册入口 | 保存/预览依赖本地结果路径与权限 |
| LOC-MEDIA-001 | `app/lib/features/media/screens/photo_grid_screen.dart` | M | 源人脸图片选择与相册权限 | Android 权限行为需真机/模拟器验证 |
| LOC-MEDIA-002 | `app/lib/features/media/screens/video_grid_screen.dart` | M | 目标图片/视频选择与限制提示 | 1 分钟/100MB 限制不能绕过 |
| LOC-AUTH-001 | `app/lib/features/auth/providers/auth_provider.dart` | S | Mock 手机号验证码登录状态 | 点击生成时登录拦截依赖它 |
| LOC-AUTH-002 | `app/lib/features/auth/screens/login_screen.dart` | M | 登录页与可选读取本机号码辅助 | 后续接真实短信/微信登录时风险集中 |
| LOC-NOTIFY-001 | `app/lib/core/services/notification_service.dart` | S | Android 本地通知初始化和生成完成/失败通知 | Android 通知权限/渠道需验证 |
| LOC-BUILD-001 | `scripts/build-release-apks.sh` | S | Release APK 打包与命名 | 产物在 `releases/`，不要提交 APK |
| LOC-TEST-001 | `app/test/` | M | Flutter/Dart 单元与 Widget 测试 | 改状态机/API/UI 后应补窄范围测试 |

## 6. 核心数据流

```text
main.dart
  -> NotificationService.initialize()
  -> MultiProvider(GenerationProvider, AuthProvider)
  -> SplashScreen
  -> AuthGate
  -> GenerationScreen
     -> PhotoGridScreen / VideoGridScreen 选择素材
     -> AuthProvider 未登录则跳 LoginScreen
     -> GenerationProvider.startGeneration()
        -> ApiService.healthCheck()
        -> VideoCompressUploadOptimizer.optimizeForUpload() [视频目标]
        -> ApiService.swapVideoJob() / swapFace()
        -> ApiService.pollSwapJob() / 下载结果
        -> ResultPreviewDialog 保存/预览
```

## 7. 生成流程状态机

`GenerationProvider` 是当前项目最重要的状态聚合点：

- 输入：`videoPath`、`faceImagePath`
- 状态：`idle -> ready -> processing -> completed/failed`
- 进度段：
  - 0.05 连接服务器
  - 0.08-0.15 视频压缩
  - 0.15-0.25 上传素材
  - 0.30-0.95 服务端处理/轮询
  - 1.0 完成
- 并发保护：`_generationRunId` 用于取消/新一轮生成后忽略旧异步回调。
- 后台语义：`setAppLifecycleInBackground()` 只在处理期间更新提示；完成/失败且处于后台才发通知。

## 8. API 与远端服务

`ApiService` 默认指向 `https://facefusion.baoganai.com`。

| 方法 | 路径 | 客户端方法 | 说明 |
|---|---|---|---|
| GET | `/api/health` | `healthCheck()` | 连接前置检查 |
| POST | `/api/swap/image` | `swapFace()` | 图片目标同步返回结果流 |
| POST | `/api/swap/video/job` | `swapVideoJob()` | 视频目标创建 job，返回 `job_id` |
| GET | `/api/swap/status/{jobId}` | `pollSwapJob()` | 4 秒轮询，最多约 35 分钟 |
| GET | `/api/swap/result/{jobId}` | `_downloadJobResult()` | 下载 mp4 到临时目录 |

风险点：
- 上传进度通过包装 `MultipartRequest` 的 byte stream 实现；修改 multipart 逻辑时必须保留 `contentLength` 与回调。
- 轮询对短暂网络失败有容忍；不要把后台网络暂不可用误判成立即失败。
- 结果路径是临时文件，预览/保存逻辑需要确保文件存在。

## 9. UI 风险点

- `GenerationScreen` 同时管理处理中、错误、完成、退出确认弹框；所有弹框改动都要关注 root navigator 与 post-frame 时机。
- 完成弹框会等待处理中弹框关闭约 180ms，避免两个弹框抢 Navigator。
- 未登录用户允许先选素材，但点击生成时进入登录；登录成功应回到原生成流程。
- 底部版本号位于生成页，改版本时不要只改 pubspec，还要同步 UI 常量。

## 10. 验证命令

常规最小验证：

```bash
cd /tmp/zfj/apps/face-swap-video/app
dart format lib test
flutter analyze
flutter test
```

涉及 Android 运行/截图：

```bash
cd /tmp/zfj/apps/face-swap-video
python3 scripts/screenshot-android.py
```

Release 打包：

```bash
cd /tmp/zfj/apps/face-swap-video
scripts/build-release-apks.sh
```

## 11. CRAG 查询命令

由于当前 `python3 -m workflow_crag.cli` 不触发 `main()`，推荐：

```bash
cd /tmp/zfj/apps/workflow-crag-starter
python3 - <<'PY'
from workflow_crag.cli import main
import sys
sys.argv = [
    'workflow-crag-starter',
    'query',
    '/tmp/zfj/apps/face-swap-video',
    '你的查询，例如 generation provider background polling',
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

刷新索引：

```bash
cd /tmp/zfj/apps/workflow-crag-starter
python3 -m workflow_crag.setup_crag /tmp/zfj/apps/face-swap-video --backend hash
```
