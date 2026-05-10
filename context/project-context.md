# face-swap-video 项目上下文

> 🔴 **Android App 项目 — 所有开发、构建、截图必须在 Android 端完成**
> minSdkVersion: Android 10 (API 29)
> 最后更新: 2026-05-10

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
- 生成方式：视频检测与换脸生成依赖远端接口，移动端不承担重模型推理。
- 交互：打开 App 直接进入生成页面；用户选择/上传素材后点击提交，然后等待远端生成结果。
- 后台转换：点击转换时不要直接进入后台转换模式；App 在前台时仍然正常转换并展示前台进度，只有用户把应用切换到后台后，才执行后台转换/后台轮询逻辑。
- 版本号：应用底部展示版本号；每次添加功能升级 minor，每次修复 bug 升级 patch；第一次发布时 major 从 0 升级到 1。
- 风格：极简，少页面、少配置、少解释，优先把主流程跑通。
- 合规：仅处理授权素材，默认展示 AI 生成/换脸提示。

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

## 目录结构

```text
apps/face-swap-video/
├── context/                 # 项目上下文
├── docs/                    # PRD / 技术方案 / 测试用例 / 实施计划
├── app/                     # Flutter Android App
│   ├── lib/
│   │   ├── main.dart
│   │   ├── providers/           # 生成任务状态、进度与前后台生命周期状态
│   │   ├── screens/             # 启动页、生成页、素材网格页
│   │   ├── services/            # 远端 API 与本地通知服务
│   │   └── utils/               # 纯工具函数：媒体类型、相册名称、生命周期判定
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
| ASCII 编译路径 | `/tmp/zfj` → `~/Desktop/致富经` |
| Skill: 截图 | `android-screenshot` |

## 阻塞点

- 远端接口已按当前客户端实现固化为：`/api/health`、`/api/swap/image`、`/api/swap/video/job`、`/api/swap/status/{jobId}`、`/api/swap/result/{jobId}`；后续若服务端协议变化，需要同步更新 `app/lib/services/api_service.dart` 与测试/文档。
- 尚未提供授权测试素材。
- 分享能力仍待产品确认；当前重点保持完成预览、保存入口与前后台通知链路稳定。

## 下一步

1. 用授权素材验证真实远端任务链路：健康检查 → 上传 → 轮询 → 下载结果。
2. 为 `GenerationProvider` 的状态流补充窄范围单元测试，覆盖取消、失败恢复与前后台切换。
3. 产品确认分享能力后，再实现结果分享入口。
4. 持续更新 PRD/技术方案/测试用例文档，确保与 Android App 现状一致。
