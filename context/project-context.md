# face-swap-video 项目上下文

> 🔴 **Android App 项目 — 所有开发、构建、截图必须在 Android 端完成**
> minSdkVersion: Android 10 (API 29)
> 最后更新: 2026-05-11

## ⚠️ 强依赖

- **这是 Android App**。禁止用 web/macOS 开发或截图替代。
- **编译**：项目在 `~/Desktop/致富经/` 含中文，Gradle/Java 不兼容，必须通过 `/tmp/zfj` ASCII 符号链接编译。
- **截图**：`scripts/screenshot-android.py`，通过 ADB 截取模拟器/真机画面。
- **模拟器**：`Medium_Phone_API_36.1`

## 技术栈

| 项 | 选择 |
|---|---|
| 框架 | Flutter 3.41.7 |
| 语言 | Dart |
| 状态管理 | Provider |
| minSdkVersion | 29 (Android 10) |
| 包名 | com.baoganai.face_swap_video |

## 产品铁律

- 形态：Android App，不是桌面端/纯 Python 工具。
- 生成方式：视频检测与换脸生成依赖远端接口，移动端不承担重模型推理；目标视频选择时限制长度不超过 1 分钟、文件不超过 100 MB，大视频上传前可在 Android 端压缩，减少上传体积与远端处理帧数。
- 交互：打开 App 直接进入生成页面；用户选择/上传素材后点击提交，然后等待远端生成结果。
- 后台转换：点击转换时不要直接进入后台转换模式；App 在前台时仍然正常转换并展示前台进度，只有用户把应用切换到后台后，才执行后台转换/后台轮询逻辑。
- 版本号：应用底部展示版本号；从 0.7.3 开始继续迭代；每次添加功能升级 minor，每次修复 bug 升级 patch；后续生成的 APK 文件名使用 `爆肝AI-v版本号[-ABI]-构建类型.apk`。
- 风格：极简，少页面、少配置、少解释，优先把主流程跑通。
- 合规：仅处理授权素材，默认展示 AI 生成/换脸提示。
- 登录：启动页后直接进入生成页；未登录用户可以先选择素材，只有点击“生成/一键开始换脸”时才弹出登录页，登录成功后返回生成页，主界面保留轻量账号入口。

## 当前阶段

| 阶段 | 状态 |
|---|---|
| 00 项目初始化 | ✅ 已完成 |
| 01 产品方向校准 | ✅ Android + 远端生成 + 极简页面 |
| 02 Android App 骨架 | ✅ Flutter 工程已创建，生成页 UI 已完成 |
| 03 远端生成 API 对接 | ✅ 已接入健康检查、图片同步换脸、视频任务创建/轮询/结果下载 |
| 04 生成页主流程 | ✅ 已接入 Provider 状态、前台进度、取消/失败/完成弹框 |
| 05 结果页/保存分享 | 🔨 已有完成预览与保存入口，分享能力待产品确认 |
| 06 合规提示与授权确认 | ✅ 已内嵌到生成页底部 |
| 07 登录/注册 | ✅ 已接入 Mock 手机号验证码登录/注册，登录页提供可选读取本机号码辅助回填；任意非空手机号与验证码可通过，后续接真实短信接口 |

## 目录结构

```text
apps/face-swap-video/
├── context/                 # 项目上下文
├── docs/                    # PRD / 技术方案 / 测试用例 / 实施计划
├── app/                     # Flutter Android App
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/                # 跨功能通用：通知服务、生命周期工具、App Logo、开屏动画
│   │   └── features/
│   │       ├── auth/            # Mock 手机号登录：provider、登录页、设备手机号辅助服务
│   │       ├── generation/      # 生成页、上传前压缩、远端 API、任务状态、进度/结果/底部组件
│   │       └── media/           # 照片/视频选择页、相册命名、媒体类型与网格组件
│   ├── test/                    # Flutter/Dart 测试
│   └── android/app/build.gradle.kts  (minSdk = 29)
├── scripts/                 # 工具脚本（在项目根 scripts/）
│   └── screenshot-android.py
├── src/face_swap_video/     # 初始化遗留 Python，仅参考
└── README.md
```

## 工具链

| 工具 | 路径 |
|---|---|
| Android 截图 | `scripts/screenshot-android.py` |
| Release APK 打包 | `scripts/build-release-apks.sh`，输出 `releases/爆肝AI-v版本号-ABI-release.apk` |
| ASCII 编译路径 | `/tmp/zfj` → `~/Desktop/致富经` |
| Skill: 截图 | `android-screenshot` |

## 阻塞点

- 远端接口已按当前客户端实现固化为：`/api/health`、`/api/swap/image`、`/api/swap/video/job`、`/api/swap/status/{jobId}`、`/api/swap/result/{jobId}`；后续若服务端协议变化，需要同步更新 `app/lib/features/generation/services/api_service.dart` 与测试/文档。
- 阿里云方案 A（OSS + `MergeVideoFace`）因接口申请需要公司资质而暂停；当前没有相关资质，不继续真实 API 调用或 App 接入。
- 方案 B 正在独立分支验证：OSS + FC Serverless GPU + FaceFusion + ACR；第一阶段不使用 SLS、不改前端界面展示。
- 分享能力仍待产品确认；当前重点保持完成预览、保存入口与前后台通知链路稳定。

## 下一步

1. 方案 B：等待用户提供阿里云 FC GPU / ACR / OSS / RAM 前置资源后，构建 FaceFusion GPU 容器并部署到 FC。
2. 用授权素材验证真实远端任务链路：健康检查 → 上传 → 轮询 → 下载结果。
3. 为 `GenerationProvider` 的状态流补充窄范围单元测试，覆盖取消、失败恢复与前后台切换。
4. 产品确认分享能力后，再实现结果分享入口。
5. 持续更新 PRD/技术方案/测试用例文档，确保与 Android App 现状一致。
