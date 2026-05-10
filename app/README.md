# face_swap_video Android App

Flutter Android 客户端，用于在授权素材前提下选择源人脸与目标视频/素材，并把换脸生成任务提交到远端服务处理。移动端负责素材选择、任务提交、前台进度展示、后台等待通知与结果预览，不在本地运行重模型推理。

## 开发与验证路径

项目原始路径可能包含中文字符，Flutter/Gradle 构建请固定在 ASCII 路径执行：

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
```

涉及依赖、Android 配置或发布前验证时再执行：

```bash
flutter build apk --debug
```

Debug APK 默认输出到：

```text
/tmp/zfj/apps/face-swap-video/app/build/app/outputs/flutter-apk/app-debug.apk
```

## 主要目录

```text
lib/
├── main.dart                    # 应用入口、Provider 注入、启动页切换
├── providers/                   # 生成任务状态与前后台生命周期状态
├── screens/                     # 启动页、生成页、素材网格页
├── services/                    # 远端 API 与本地通知服务
└── utils/                       # 纯工具函数：媒体类型、相册名称、生命周期、文件名展示
test/                            # Flutter/Dart 测试
android/app/build.gradle.kts      # Android 包名、SDK 与构建配置
```

## 维护约束

- 不修改包名 `com.baoganai.face_swap_video`、minSdk 或接口协议，除非有明确产品要求。
- 不改变主流程：打开 App → 选择素材 → 提交远端任务 → 查看进度/结果。
- App 前台时保持前台进度展示；只有用户切到后台后才依赖后台等待与完成通知。
- 构建产物、截图、APK 和 Gradle/Flutter 缓存不要提交到 Git。
