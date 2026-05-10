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
| 03 远端生成 API 对接 | 🔨 待设计 |
| 04 生成页主流程 | 🔨 已完成 UI（Provider 状态模拟） |
| 05 结果页/保存分享 | ⏳ 待规划 |
| 06 合规提示与授权确认 | ✅ 已内嵌到生成页底部 |

## 目录结构

```text
apps/face-swap-video/
├── context/                 # 项目上下文
├── docs/                    # PRD / 技术方案 / 测试用例 / 实施计划
├── app/                     # Flutter Android App
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/generation_screen.dart
│   │   └── providers/generation_provider.dart
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

- 尚未提供远端视频生成接口协议：上传字段、任务轮询、结果 URL、错误码、鉴权。
- 尚未提供授权测试素材。
- 「保存/分享」功能仅占位，未对接真实存储。

## 下一步

1. 定义远端生成接口协议。
2. 实现真实 API 调用替换 Provider 中的模拟逻辑。
3. 实现结果视频的保存与分享。
4. 更新 PRD/技术方案/测试用例文档。
