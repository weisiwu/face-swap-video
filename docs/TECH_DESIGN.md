# 技术方案设计：爆肝AI 视频换脸 Android App

## 1. 当前架构

```text
Android Flutter App
  ↓
GenerationScreen（素材选择、账号入口、进度/结果 UI）
  ↓
GenerationProvider（生成状态机、前后台生命周期、进度）
  ↓
ApiService（远端 FaceFusion API）
  ↓
https://facefusion.baoganai.com
```

登录为独立轻量状态：

```text
SplashScreen
  ↓
AuthGate（当前默认进入 GenerationScreen）
  ↓
GenerationScreen
  ├─ 未登录点击生成 → LoginScreen
  └─ 登录成功返回 → startGeneration
```

## 2. 技术栈

| 模块 | 当前选择 |
|---|---|
| App 框架 | Flutter 3.41.7 |
| 语言 | Dart |
| 状态管理 | Provider / ChangeNotifier |
| Android minSdk | API 29 |
| 网络 | package:http multipart upload + stream download |
| 本地媒体 | file_picker、photo_manager、video_thumbnail、video_player、video_compress |
| 通知 | flutter_local_notifications |
| 外链 | url_launcher |
| 测试 | flutter_test |

## 3. 关键模块

### 3.1 `main.dart`

- 初始化 `NotificationService`。
- 注入 `GenerationProvider` 和 `AuthProvider`。
- 展示启动页，启动页结束后进入 `AuthGate`。
- 监听 App 生命周期，把前后台状态同步给 `GenerationProvider`。

### 3.2 `GenerationScreen`

职责：

- 展示品牌头部、素材选择卡片、合规提示、版本号、吸底生成按钮。
- 处理素材选择入口和结果预览弹窗。
- 顶部展示轻量账号入口，长按可退出登录。
- 点击生成时检查登录态；未登录则跳转 `LoginScreen`。

维护约束：

- 不改变主流程：打开 App → 选择素材 → 提交远端任务 → 查看进度/结果。
- 文件仍偏大，后续应优先拆出进度弹窗、结果弹窗、素材卡片和吸底按钮组件。

### 3.3 `GenerationProvider`

职责：

- 保存源人脸、目标素材、任务状态、错误、结果路径。
- 调用 `VideoUploadOptimizer` 对大视频做上传前压缩，再调用 `ApiService.swapFace()`。
- 维护上传、处理、下载进度。
- 根据生命周期状态区分前台进度与后台等待。
- 完成后触发本地通知和结果展示。

关键约束：

- 只有 `_status == processing && _isAppInBackground` 时才视为后台转换活跃。
- 进度不允许明显回退；失败/取消后状态应可恢复。

### 3.4 `ApiService`

默认 Base URL：`https://facefusion.baoganai.com`

当前接口：

| 能力 | 方法 | 路径 |
|---|---|---|
| 健康检查 | GET | `/api/health` |
| 图片换脸 | POST multipart | `/api/swap/image` |
| 创建视频任务 | POST multipart | `/api/swap/video/job` |
| 查询任务状态 | GET | `/api/swap/status/{jobId}` |
| 下载任务结果 | GET | `/api/swap/result/{jobId}` |

行为：

- 图片目标：上传 source/target，服务端同步返回结果流。
- 视频目标：上传 source/target 创建 job，客户端每 4 秒轮询状态，完成后下载 mp4。
- 上传和下载均通过 stream 统计进度。
- 轮询总超时 35 分钟；状态请求超时 15 秒。

### 3.5 `AuthProvider` / `LoginScreen`

当前实现边界：

- Mock 手机号验证码登录，不请求真实后端 Auth API。
- `sendCode()` 只触发 60 秒倒计时。
- `loginWithSms()` 校验手机号非空、验证码为 6 位数字，然后设置本地内存登录态。
- 登录态不持久化，重启 App 后恢复未登录。
- `DevicePhoneService` 用于在用户主动点击后尝试读取 Android 主卡手机号作为辅助回填。

后续如接真实账号服务，应新增 `AuthApiService` 和 `AuthStorage`，不要塞进 FaceFusion `ApiService`。

## 4. 目录结构

```text
app/lib/
├── main.dart
├── core/
│   ├── screens/splash_screen.dart
│   ├── services/notification_service.dart
│   ├── utils/app_lifecycle_background.dart
│   └── widgets/                  # App Logo、开屏标识 Painter 等跨功能 UI
├── features/
│   ├── auth/
│   │   ├── providers/auth_provider.dart
│   │   ├── screens/auth_gate.dart
│   │   ├── screens/login_screen.dart
│   │   ├── services/device_phone_service.dart
│   │   └── widgets/auth_background.dart
│   ├── generation/
│   │   ├── providers/generation_provider.dart
│   │   ├── screens/generation_screen.dart
│   │   ├── services/api_service.dart
│   │   ├── utils/transfer_progress_label.dart
│   │   └── widgets/              # Header、素材卡、进度弹窗、结果预览、吸底 Footer
│   └── media/
│       ├── screens/photo_grid_screen.dart
│       ├── screens/video_grid_screen.dart
│       ├── utils/                # 相册名称、文件名、媒体类型
│       └── widgets/              # 相册切换 Sheet、网格 Tile、权限提示
```

## 5. 构建与验证

项目路径含中文时，必须使用 ASCII 路径构建：

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
flutter test
flutter build apk --debug
```

Release 脚本：

```bash
cd /tmp/zfj/apps/face-swap-video
scripts/build-release-apks.sh
```

APK 命名规则：`爆肝AI-v版本号[-ABI]-构建类型.apk`。

## 6. 风险与后续优化

| 风险 | 应对 |
|---|---|
| `generation_screen.dart` 继续变大 | 已拆出 header、素材卡片、进度弹窗、结果弹窗、footer；后续新增 UI 优先放入独立 widget |
| 登录仍是 Mock | 接真实短信 API、token 存储、登录态恢复 |
| 真实素材链路未充分验证 | 用授权素材跑健康检查→上传→轮询→下载→保存 |
| 分享/历史记录未定义 | 等产品确认后再补生成记录和系统分享 |
| 远端接口协议变化 | 同步更新 `ApiService`、测试和本文档 |
