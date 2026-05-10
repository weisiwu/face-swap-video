# face-swap-video

> 授权素材下的视频人脸检测与换脸工具：输入源人脸与目标视频，检测目标视频中的人脸轨迹，在合规授权前提下生成带水印/元数据标记的换脸视频。

## 项目边界

本项目只面向以下场景：

- 用户拥有或已获得明确授权的人脸素材；
- 内部创意、影视预演、虚拟形象、数字人内容生产；
- 明确标注 AI 生成或换脸水印；
- 保留处理日志、授权记录与输出元数据。

本项目不支持：

- 未授权替换真实人物人脸；
- 冒充公众人物、诈骗、色情、诽谤、身份欺骗等用途；
- 去水印、规避检测、隐藏 AI 生成痕迹。

## 当前目录

```text
face-swap-video/
├── app/                         # Flutter Android App
│   ├── lib/
│   │   ├── main.dart
│   │   ├── providers/
│   │   ├── screens/
│   │   ├── services/
│   │   └── utils/
│   ├── test/
│   └── android/app/build.gradle.kts
├── context/
│   └── project-context.md
├── docs/
│   ├── PRD.md
│   ├── TECH_DESIGN.md
│   ├── TEST_CASES.md
│   └── IMPLEMENTATION_PLAN.md
├── scripts/                     # Android 验证/截图等工具脚本
├── server/                      # 远端 FaceFusion 服务辅助代码
└── src/face_swap_video/         # 初始化遗留 Python，仅参考
```

## Android App 快速验证

> 项目原始路径可能包含中文，Flutter/Gradle 构建请优先使用 `/tmp/zfj` ASCII 路径。

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
flutter test
flutter build apk --debug
```

Debug APK 输出路径：

```text
/tmp/zfj/apps/face-swap-video/app/build/app/outputs/flutter-apk/app-debug.apk
```

## 当前状态

Android Flutter App 已接入远端换脸接口：选择源人脸与目标素材后提交任务，App 展示前台进度，并在应用切到后台后继续等待远端任务完成。移动端不承担重模型推理。
