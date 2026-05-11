# face-swap-video

> **爆肝AI Android 视频换脸 App**：在授权素材前提下选择源人脸与目标图片/视频，把生成任务提交到远端 FaceFusion 服务，移动端负责素材选择、任务提交、前台进度、后台等待通知、结果预览与保存入口。

## 1. 项目边界

本项目只面向以下场景：

- 用户拥有或已获得明确授权的人脸素材；
- 内部创意、影视预演、虚拟形象、数字人内容生产；
- 明确标注 AI 生成/换脸提示；
- 移动端负责交互和任务编排，远端服务负责重模型推理。

本项目不支持：

- 未授权替换真实人物人脸；
- 冒充公众人物、诈骗、色情、诽谤、身份欺骗等用途；
- 去水印、规避检测、隐藏 AI 生成痕迹；
- 在 Android 端本地运行重模型。

## 2. 当前状态

| 模块 | 状态 |
|---|---|
| Android App 骨架 | ✅ Flutter Android 客户端已创建 |
| 远端 FaceFusion API | ✅ 已接入健康检查、图片同步换脸、视频任务创建/轮询/结果下载 |
| 生成主流程 | ✅ 素材选择、上传前大视频压缩、上传进度、视频任务轮询、结果下载、完成弹框 |
| 前后台处理 | ✅ 前台展示进度；仅 App 切到后台后进入后台等待/通知语义 |
| 结果处理 | ✅ 结果预览与保存入口；分享能力待产品确认 |
| 登录/注册 | ✅ Mock 手机号验证码登录；点击生成时才要求登录 |
| 手机号读取 | ✅ 登录页可选辅助入口；用户主动点击后才尝试读取本机号码 |
| 目录重构 | ✅ `lib/core + lib/features/*` 分层，主要大页面已拆出独立 widgets |
| Release 打包 | ✅ 提供脚本；正式 release signing 待收口 |

> 注意：当前登录仍是 Mock，本地内存态；任意非空手机号 + 6 位验证码可通过。它只用于打通登录触发、返回生成页、协议勾选和倒计时体验，不代表已接入真实短信或账号体系。

## 3. 技术栈

| 项 | 选择 |
|---|---|
| 客户端 | Flutter Android App |
| 语言 | Dart |
| 状态管理 | Provider |
| Android minSdk | API 29 / Android 10 |
| 包名 | `com.baoganai.face_swap_video` |
| 当前版本 | `1.6.0+2016` |
| 远端服务 | `https://facefusion.baoganai.com` |

性能优化策略：

- Android 端对大视频上传前先压缩到 960×540 / 24fps，减少上行体积；
- Cloudflare Tunnel 固定使用 HTTP/2，规避当前网络环境下 QUIC 频繁 timeout/reconnect 导致的上传抖动；
- 服务端视频任务单 worker 串行执行，避免多个 CoreML/FaceFusion 任务并发抢资源导致变慢或失败；
- 服务端对目标视频再做 720p / 24fps 保护性预处理，并使用 `ultrafast` 输出 preset，优先保证移动端等待时间。

主要依赖：

- `provider`：生成与登录状态管理；
- `photo_manager`：照片/视频相册选择；
- `file_picker`：文件选择；
- `http`：远端 API 调用；
- `video_player` / `video_thumbnail`：结果预览与视频缩略图；
- `video_compress`：大视频上传前压缩到移动端友好的分辨率/FPS，降低上传体积与服务端处理帧数；
- `flutter_local_notifications`：后台完成通知；
- `url_launcher`：用户协议/隐私政策跳转。

## 4. 当前目录

```text
face-swap-video/
├── app/                         # Flutter Android App
│   ├── lib/
│   │   ├── main.dart            # 应用入口、Provider 注入、开屏到主流程切换
│   │   ├── core/                # 跨功能通用：通知、生命周期、Logo、开屏动画
│   │   └── features/
│   │       ├── auth/            # Mock 登录、登录页、手机号辅助读取
│   │       ├── generation/      # 生成主流程、远端 API、状态、进度/结果/底部组件
│   │       └── media/           # 照片/视频选择页、相册工具和媒体组件
│   ├── test/                    # Flutter/Dart 测试
│   └── android/app/build.gradle.kts
├── context/
│   └── project-context.md       # Hermes 项目上下文，切换项目时优先读取
├── docs/
│   ├── PRD.md
│   ├── TECH_DESIGN.md
│   ├── TEST_CASES.md
│   ├── AUTH_LOGIN_REGISTER_DESIGN.md
│   └── IMPLEMENTATION_PLAN.md
├── scripts/
│   ├── build-release-apks.sh    # Release APK 打包脚本
│   └── screenshot-android.py    # Android 真机/模拟器截图脚本
├── tasks/                       # 后续待办任务拆解
├── server/                      # 远端 FaceFusion 服务辅助代码
└── src/face_swap_video/         # 初始化遗留 Python，仅参考
```

## 5. 主流程

```text
启动页
  ↓
生成页
  ↓
选择源人脸 + 目标图片/视频
  ↓
点击生成
  ├─ 未登录 → LoginScreen Mock 手机号验证码登录 → 返回生成页
  └─ 已登录 → 大视频上传前压缩 → 提交远端 FaceFusion API
  ↓
前台进度 / 后台等待通知
  ↓
结果预览 / 保存
```

关键约束：

- App 打开后不强制登录，用户可以先选择素材；
- 只有点击“生成/一键开始换脸”时才要求登录；
- App 前台时必须正常显示进度，不能点击生成后直接进入后台模式；
- 只有用户把 App 切到后台后，才进入后台等待/通知语义；
- 生成结果必须保留 AI 生成/换脸提示与授权素材提醒。

## 6. 远端 API

默认服务地址：

```text
https://facefusion.baoganai.com
```

当前客户端使用的接口：

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `/api/health` | 健康检查 |
| `POST` | `/api/swap/image` | 图片同步换脸 |
| `POST` | `/api/swap/video/job` | 创建视频换脸任务 |
| `GET` | `/api/swap/status/{jobId}` | 轮询视频任务状态 |
| `GET` | `/api/swap/result/{jobId}` | 下载视频任务结果 |

如服务端协议变化，需要同步更新：

- `app/lib/features/generation/services/api_service.dart`
- `app/test/api_service_test.dart`
- `docs/TECH_DESIGN.md`
- `context/project-context.md`

## 7. Android App 快速验证

> 项目原始路径可能包含中文，Flutter/Gradle 构建请固定使用 `/tmp/zfj` ASCII 路径。

```bash
cd /tmp/zfj/apps/face-swap-video/app
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Debug APK 输出路径：

```text
/tmp/zfj/apps/face-swap-video/app/build/app/outputs/flutter-apk/app-debug.apk
```

## 8. Release APK 打包

```bash
cd /tmp/zfj/apps/face-swap-video
scripts/build-release-apks.sh
```

脚本输出目录：

```text
releases/
```

APK 命名规则：

```text
爆肝AI-v版本号[-ABI]-构建类型.apk
```

说明：

- `releases/` 已加入 `.gitignore`，不要提交 APK 产物；
- 脚本每次构建前会清理旧 APK，避免不同版本混杂；
- 当前正式 release signing 仍待收口，详见 `tasks/02-release-signing.md`。

## 9. 测试与文档

核心文档：

- `docs/PRD.md`：产品需求与边界；
- `docs/TECH_DESIGN.md`：架构、接口、目录、构建方案；
- `docs/TEST_CASES.md`：手工与自动化测试用例；
- `docs/AUTH_LOGIN_REGISTER_DESIGN.md`：手机号验证码登录注册设计；
- `docs/IMPLEMENTATION_PLAN.md`：阶段实施计划；
- `context/project-context.md`：Agent 工作上下文。

当前测试重点：

- 登录 Provider 状态、验证码倒计时、协议校验；
- 远端 API 健康检查、任务创建、轮询、结果下载；
- 相册名称、媒体文件类型、选择文件名；
- 生成页 widget 流程与前后台状态。

## 10. 待办任务

当前后续任务以独立 task 文件维护：

- `tasks/01-auth-login-register.md`：把 Mock 登录演进为真实短信验证码与账号体系；
- `tasks/02-release-signing.md`：正式 release signing、keystore 管理与 APK 签名验证。

完成某个任务后，应删除对应 task 文件，剩余 task 文件数量即项目进度。