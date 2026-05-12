# 更新日志

## v1.8.1 — 2026-05-12

### 下载地址

- Android 真机优先安装包（arm64-v8a）：https://github.com/weisiwu/face-swap-video/releases/download/v1.8.1/baogan-ai-v1.8.1-arm64-v8a-release.apk
- Android 老设备兼容包（armeabi-v7a）：https://github.com/weisiwu/face-swap-video/releases/download/v1.8.1/baogan-ai-v1.8.1-armeabi-v7a-release.apk
- Android 模拟器包（x86_64）：https://github.com/weisiwu/face-swap-video/releases/download/v1.8.1/baogan-ai-v1.8.1-x86_64-release.apk

### 改动内容

- 服务端新增并默认启用 `preview` 低清快速模式：360p / 12fps / output quality 50，用于更快产出 MVP 预览结果。
- `FF_VIDEO_PROFILE=low` / `mvp` 自动映射到 `preview`，保留 `fast` 与 `high_quality` 模式。
- 服务端状态接口 `/api/swap/status/{job_id}` 增加阶段信息：`stage`、`stage_label`、`progress`、`video_profile`。
- 服务端处理阶段覆盖：排队中、预处理视频、检测人脸、逐帧换脸、编码输出、处理完成、处理失败、已取消。
- App 端处理弹窗文案优化为“服务端正在逐帧换脸，预计需要 20～40 秒”，避免用户误以为卡住。
- App 端轮询服务端阶段并展示更具体的处理文案，例如检测人脸、编码输出。
- 优化处理结果保存/预览相关提示弹窗样式，成功与失败状态更清晰。
- 简化结果预览界面，减少遮挡视频画面的居中文案与播放遮罩。
- 版本号升级到 `1.8.1+4024`，底部版本展示同步更新。

### 验证记录

- `python3 -m py_compile server/api/server.py` 通过。
- `python3 -m pytest server/api/test_api_server_config.py -q`：7 passed。
- `dart format lib test` 通过。
- `flutter analyze`：No issues found。
- `flutter test`：All tests passed。
- 远端 `https://facefusion.baoganai.com/api/health` 已验证返回 `video_profile=preview`、`target_max_width=360`、`target_fps=12`、`output_video_quality=50`。
- 使用测试素材完成远端真实任务，状态阶段覆盖 `detecting_face → swapping_frame → completed`。
- Debug 包已安装并启动验证 Android 真机主界面。
