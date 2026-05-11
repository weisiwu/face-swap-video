# 日志使用与问题诊断指南

> 适用版本：v1.8.0+
> 日志框架：`lib/core/services/app_logger.dart`

本指南说明 App 内置的本地文件日志如何工作、怎么取出、以及如何通过日志快速定位换脸/上传/下载/登录等典型问题。

---

## 1. 日志位于哪里

- **设备路径**：`<应用文档目录>/logs/app.log`
  - Android 实际路径：`/data/data/com.baoganai.face_swap_video/app_flutter/logs/app.log`
- **滚动策略**：单文件上限 1 MB，最多保留 4 份
  - 当前：`app.log`
  - 历史：`app.1.log`、`app.2.log`、`app.3.log`（数字越大越旧；超出会被删除）
- **行格式**：

  ```
  2026-05-12T02:38:53.321 [I] [GenerationProvider] startGeneration runId=1 ...
  2026-05-12T02:38:55.901 [E] [ApiService] pollSwapJob terminal jobId=abc ... | error=...
  <stack trace>
  ```

  - 时间戳：ISO‑8601 本地时间，带毫秒
  - 等级：`D` debug / `I` info / `W` warn / `E` error
  - 标签：模块名（见下表）
  - 正文：`key=value` 形式的结构化字段，便于 grep
  - `error=` 与 stack trace 仅出现在 `W` / `E`

---

## 2. 怎么把日志取出来

### 2.1 通过 ADB（推荐）

```bash
# 列出现有日志文件
adb shell run-as com.baoganai.face_swap_video ls app_flutter/logs

# 拷贝当前日志到本机
adb shell run-as com.baoganai.face_swap_video cat app_flutter/logs/app.log > app.log

# 拷贝最近一段历史
adb shell run-as com.baoganai.face_swap_video cat app_flutter/logs/app.1.log > app.1.log

# 只看错误/警告
adb shell run-as com.baoganai.face_swap_video cat app_flutter/logs/app.log | grep -E '\[(W|E)\]'
```

> `run-as` 仅在 debug 包或 `android:debuggable="true"` 时可用。Release 用户日志请引导用户使用"分享日志"功能（待产品确认；当前未开放 UI 入口）。

### 2.2 通过 logcat 实时观察

应用在 `debugPrint` 中也会输出每一行同样的日志，因此实时调试可以：

```bash
adb logcat -s flutter
```

调试时无需先 init 日志，每一行也会即时打印。

---

## 3. 模块（Tag）速查

| Tag | 来源 | 关键事件 |
|---|---|---|
| `App` | `lib/main.dart` | 启动、前/后台生命周期切换 |
| `AppLogger` | `lib/core/services/app_logger.dart` | logger 初始化路径 |
| `AuthProvider` | `lib/features/auth/providers/auth_provider.dart` | 登录/验证码/登出（手机号已脱敏为 `***1234`） |
| `NotificationService` | `lib/core/services/notification_service.dart` | 通知 channel 初始化、完成/失败通知触发 |
| `PhotoGrid` / `VideoGrid` | `lib/features/media/screens/*` | 相册权限、相册数量、选片来源、视频被拒原因 |
| `GenerationProvider` | `lib/features/generation/providers/generation_provider.dart` | 选材、`startGeneration` 各阶段、取消、前后台切换 |
| `VideoUploadOptimizer` | `lib/features/generation/services/video_upload_optimizer.dart` | 是否压缩、压缩前后字节、压缩耗时、压缩失败回退 |
| `ApiService` | `lib/features/generation/services/api_service.dart` | 健康检查、上传里程碑、视频任务创建、轮询、下载、错误码 |
| `ResultVideoPreview` | `lib/features/generation/widgets/result_video_preview.dart` | 结果视频预览初始化成功的尺寸/时长 / 失败堆栈 |
| `GenerationScreen` | `lib/features/generation/screens/generation_screen.dart` | 保存到系统相册：开始/成功/失败、耗时 |

---

## 4. 一次完整成功的换脸日志长什么样

理想情况下，按时间顺序应能看到下面这条主线（关键行示意，省略次要进度）：

```text
[I] [App] app starting up
[I] [AppLogger] logger initialized at .../logs/app.log
[I] [NotificationService] initialize done channel=generation_status
[I] [AuthProvider] loadSavedSession restored phone=***1234
[I] [VideoGrid] requestPermission result=PermissionState.authorized ...
[I] [VideoGrid] select video from album path=... durationSec=18
[I] [GenerationProvider] setVideoPath path=...
[I] [PhotoGrid] select photo from album path=...
[I] [GenerationProvider] setFaceImagePath path=...
[I] [GenerationProvider] startGeneration runId=1 videoPath=... faceImagePath=...
[I] [ApiService] healthCheck -> GET https://facefusion.baoganai.com/api/health
[I] [ApiService] healthCheck status=200 ok=true elapsedMs=312
[I] [GenerationProvider] startGeneration runId=1 isVideoTarget=true
[I] [VideoUploadOptimizer] compress start originalBytes=18234112 path=...
[I] [VideoUploadOptimizer] compress done originalBytes=18234112 optimizedBytes=4321088 elapsedMs=4831 path=...
[I] [ApiService] swapVideoJob -> POST .../api/swap/video/job sourceBytes=132011 targetBytes=4321088 ...
[I] [ApiService] upload start totalBytes=4453512
[I] [ApiService] upload progress 25% sentBytes=1113378 totalBytes=4453512 elapsedMs=621
[I] [ApiService] upload progress 50% ...
[I] [ApiService] upload progress 75% ...
[I] [ApiService] upload progress 100% ...
[I] [ApiService] upload finished sentBytes=4453512 totalBytes=4453512 elapsedMs=2440
[I] [ApiService] swapVideoJob response status=200 elapsedMs=2511 bodyBytes=58
[I] [ApiService] swapVideoJob jobId=abc-123
[I] [GenerationProvider] startGeneration jobId=abc-123 runId=1
[I] [ApiService] pollSwapJob start jobId=abc-123
[I] [ApiService] pollSwapJob jobId=abc-123 pollCount=1 elapsedSec=4 status=processing serverProgress=0.05 resolvedProgress=0.080
... （周期性 pollSwapJob 行）
[I] [ApiService] pollSwapJob jobId=abc-123 pollCount=23 elapsedSec=92 status=completed serverProgress=1.0 resolvedProgress=1.000
[I] [ApiService] downloadJobResult start jobId=abc-123 url=...
[I] [ApiService] downloadJobResult writing jobId=abc-123 outputPath=/tmp/swapped_*.mp4 totalBytes=2934821
[I] [ApiService] downloadJobResult done jobId=abc-123 downloadedBytes=2934821 elapsedMs=1822
[I] [GenerationProvider] startGeneration completed runId=1 resultPath=... totalMs=104238
[I] [ResultVideoPreview] initialize done size=960x540 durationMs=18000
[I] [GenerationScreen] saveResultVideo start path=... bytes=2934821
[I] [GenerationScreen] saveResultVideo success title=face_swap_*.mp4 elapsedMs=412
```

定位失败/卡住时，先在日志里找这条主线，看看停在哪一步。

---

## 5. 按现象快速定位

### 5.1 「点了生成，立刻失败 / 提示无法连接」

```bash
grep -E 'healthCheck|startGeneration ApiException' app.log
```

- `healthCheck ok=false` → 服务器或隧道不可达
- `healthCheck` 抛异常 → 客户端网络/DNS 问题（看 `error=`）
- 健康检查通过却仍报错 → 看后续 `swapVideoJob` 或 `swapFace` 的 `non-200` / 异常栈

### 5.2 「上传慢 / 一直卡在上传」

```bash
grep -E 'upload (start|progress|finished|aborted)|compress ' app.log
```

- 没有 `upload start` → 还停在压缩阶段，看 `VideoUploadOptimizer compress`
- `upload progress 25%` 间隔很久 → 网络上行带宽不足
- `upload aborted` → 上传过程中流被关闭，常见于切到后台被系统断网或服务端拒绝

附带的 `sentBytes` / `totalBytes` / `elapsedMs` 可以直接算出实测上行速率。

### 5.3 「上传成功但一直转圈，最后超时」

```bash
grep -E 'pollSwapJob' app.log
```

关注：

- `status=processing`、`serverProgress` 是否持续推进
- `transient network error` 行：偶发出现是正常重连；连续大量出现说明客户端与服务端心跳异常
- `pollSwapJob timeout jobId=... totalSec=2100` → 服务端卡住超过 35 分钟
- `pollSwapJob terminal ... status=failed error=...` → 服务端明确失败，错误原文已记录

### 5.4 「报"没有检测到人脸"或"目标视频中没有检测到可替换的人脸"」

```bash
grep -E 'pollSwapJob terminal|swapVideoJob non-200' app.log
```

错误原文会在 `error=` 字段保留，前端的中文提示是通过 `_userFriendlyProcessingError` 转译；当原文与中文不一致时，以日志里的原文为准排查模型/素材问题。

### 5.5 「下载完成但播放失败 / 黑屏」

```bash
grep -E 'downloadJobResult|ResultVideoPreview' app.log
```

- `downloadJobResult done downloadedBytes=...` 字节数小到不正常（如 < 100KB）→ 服务端返回的是错误占位文件
- `downloadedBytes` 与 `totalBytes` 不一致 → 下载被截断
- `ResultVideoPreview initialize failed` → 文件能下载但解码失败，配合下载字节数判断是否文件损坏

### 5.6 「保存到相册失败」

```bash
grep -E 'saveResultVideo' app.log
```

- `saveResultVideo file missing path=...` → 临时目录被系统清理或 runId 已切换
- `saveResultVideo failed` 的 stack trace 通常包含 `PhotoManager` / 权限相关原因

### 5.7 「后台转换没收到通知」

```bash
grep -E 'lifecycle|setAppLifecycleInBackground|NotificationService' app.log
```

- 必须先看到 `[App] lifecycle ... isBackground=true` 后再看到 `setAppLifecycleInBackground isBackground=true`，否则说明没识别到后台
- 完成时应有 `showGenerationCompleted` 一行；若只有 `showGenerationCompleted` 但用户没看到通知 → 系统通知权限被拒绝

### 5.8 「登录卡住 / 验证码没反应」

```bash
grep -E 'AuthProvider' app.log
```

`sendCode` / `loginWithSms` 的 info 行会按顺序出现；缺失 `loginWithSms success` 表示 `_sessionStore.save` 抛错（e 行有完整栈）。

### 5.9 「相册不显示视频 / 只能从文件管理器选」

```bash
grep -E '(Photo|Video)Grid' app.log
```

- `requestPermission result=...` 中 `isAuth=false hasAccess=false` → 系统层拒绝
- `loadAlbums count=0` → 权限通过但相册空，多见于模拟器
- `video rejected by limits ... reason=...` → 超 1 分钟或 100 MB 被前端拒绝，已记录拒绝原因

---

## 6. 常用 grep 片段

```bash
# 一次完整生成的所有行（按 runId）
grep 'runId=1' app.log

# 一个具体 job 的所有事件
grep 'jobId=abc-123' app.log

# 仅看错误与警告
grep -E '\[(W|E)\]' app.log

# 看本次启动以来所有阶段切换
grep -E 'startGeneration|pollSwapJob start|downloadJobResult start|saveResultVideo' app.log

# 估算上传速率：取每次 upload finished 行
grep 'upload finished' app.log

# 估算服务端处理耗时（completed 那一行的 elapsedSec）
grep 'pollSwapJob.*status=completed' app.log
```

---

## 7. 隐私与合规

- 手机号在日志里始终掩码为 `***1234` 形式，不写明文。
- 文件路径会写明（用于诊断），不会写文件内容。
- 验证码不写入日志。
- HTTP 响应体仅在异常情况下截断到 500 字符记录。

如果排查需要更多明文信息（如完整响应 body），优先在本地 debug 构建里临时加日志，不要长期开启在 release。

---

## 8. 给开发者新增日志的约定

1. 通过 `appLogger` 单例：`appLogger.i(_logTag, 'message key=value')`。
2. **每个文件用一个本地 `const String _logTag = 'XxxYyy'`**，放在所有 `import` 之后。
3. 字段使用 `key=value`，多个字段空格分隔，避免使用逗号，方便 `grep` / `awk`。
4. 涉及耗时操作请配 `Stopwatch` 输出 `elapsedMs=`。
5. 异常用 `appLogger.e(tag, msg, error, stack)`，禁止 `print` / 裸 `debugPrint`。
6. 不要把验证码、token、明文手机号写进日志。
7. 写在循环里的日志要做"里程碑式"采样（参见 `_trackUploadProgress` 的 25% 阈值），避免刷屏。

