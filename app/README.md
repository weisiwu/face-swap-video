# face_swap_video Android App

Flutter Android 客户端，用于在授权素材前提下选择源人脸与目标图片/视频，并把换脸生成任务提交到远端服务处理。移动端负责素材选择、任务提交、前台进度展示、后台等待通知与结果预览，不在本地运行重模型推理。

## 开发与验证路径

项目原始路径可能包含中文字符，Flutter/Gradle 构建请固定在 ASCII 路径执行：

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
flutter test
flutter build apk --debug
```

Debug APK 默认输出到：

```text
/tmp/zfj/apps/face-swap-video/app/build/app/outputs/flutter-apk/app-debug.apk
```

## 主要目录

```text
lib/
├── main.dart                    # 应用入口、Provider 注入、启动页切换、生命周期同步
├── core/                        # 跨功能通用服务、工具、品牌组件和开屏动画
└── features/
    ├── auth/                    # Mock 登录、登录页、手机号辅助读取
    ├── generation/              # 生成主流程、远端 API、生成页组件
    └── media/                   # 照片/视频选择页、相册工具和媒体组件

test/                            # Flutter/Dart 测试
android/app/build.gradle.kts      # Android 包名、SDK 与构建配置
```

## 当前主流程

```text
启动页
  ↓
生成页
  ↓
选择源人脸 + 目标图片/视频
  ↓
点击生成
  ├─ 未登录 → LoginScreen Mock 手机号验证码登录 → 返回生成页
  └─ 已登录 → 提交远端 FaceFusion API
  ↓
前台进度 / 后台等待通知
  ↓
结果预览 / 保存
```

## 维护约束

- 不修改包名 `com.baoganai.face_swap_video`、minSdk 或远端接口协议，除非有明确产品要求。
- 不改变主流程：打开 App → 选择素材 → 提交远端任务 → 查看进度/结果。
- App 前台时保持前台进度展示；只有用户切到后台后才进入后台等待/通知语义。
- 登录当前为 Mock，不应误写成已接真实短信或 token 持久化。
- 构建产物、截图、APK 和 Gradle/Flutter 缓存不要提交到 Git。
