# 实施计划：爆肝AI 视频换脸 Android App

> 本文档已清理早期 Python CLI / dry-run 方案，仅保留当前 Android App 事实和下一步实施路线。

## 当前已完成

| 模块 | 状态 |
|---|---|
| Flutter Android 工程 | ✅ 已完成 |
| 启动页 → 生成页 | ✅ 已完成 |
| 素材选择 | ✅ 已完成 |
| 远端健康检查 | ✅ 已完成 |
| 图片同步换脸接口 | ✅ 已完成 |
| 视频任务创建/轮询/结果下载 | ✅ 已完成 |
| 上传/下载/处理进度 | ✅ 已完成 |
| 前台进度与后台等待区分 | ✅ 已完成 |
| 完成通知 | ✅ 已完成 |
| 结果预览与保存入口 | ✅ 已完成 |
| Mock 手机号验证码登录 | ✅ 已完成 |
| 版本号底部展示 | ✅ 已完成 |

## P0：真实链路验证

目标：用授权测试素材跑完整远端链路，确认当前 App 可真实产出结果。

任务：

1. 准备授权源人脸图片和目标图片/视频。
2. 在 Android 真机或模拟器上选择素材。
3. 验证健康检查、上传、服务端处理、轮询、下载、预览、保存。
4. 记录失败点：网络、接口返回、状态轮询、下载文件、相册保存。

验收：

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
flutter test
flutter build apk --debug
```

并完成一次真机端到端人工验证。

## P1：GenerationProvider 状态测试补齐

目标：降低核心状态流回归风险。

建议新增/补充测试：

- 取消处理中任务后恢复到可再次生成状态。
- 失败后 dismissError 正确清理错误状态。
- 前后台切换只影响后台提示，不改变任务本身。
- 生成完成后再次生成会清理旧结果路径。
- 上传/下载/轮询阶段进度文案稳定。

涉及文件：

- `app/lib/features/generation/providers/generation_provider.dart`
- `app/test/generation_provider_test.dart`
- `app/lib/features/generation/utils/transfer_progress_label.dart`
- `app/test/transfer_progress_label_test.dart`

## P2：登录注册重新收口

当前事实：登录是 Mock，本地内存态；用户可先选素材，点击生成时才登录。

后续拆分：

1. 明确真实 Auth API：发送验证码、登录/注册、刷新 token、退出登录、当前用户。
2. 新增 `AuthApiService`，与 FaceFusion `ApiService` 解耦。
3. 新增安全存储或本地存储，支持重启恢复登录态。
4. 生成接口带登录态时，再定义 jobId 与 userId 的绑定方式。
5. 更新登录页测试和主流程 widget 测试。

不再采用“启动页后强制进入登录页”的旧方案，除非产品重新确认。

## P3：拆分 `generation_screen.dart`

目标：降低单文件维护风险。

建议顺序：

1. `widgets/generation_header.dart`
2. `widgets/material_picker_card.dart`
3. `widgets/generation_progress_dialog.dart`
4. `widgets/result_preview_dialog.dart`
5. `widgets/sticky_generation_footer.dart`

每次拆分要求：

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
flutter test
```

如涉及 UI 行为，再跑 debug build 和 Android 截图验证。

## P4：结果记录与分享能力

等待产品确认后再实施：

- 我的生成记录。
- 历史结果重新查看。
- 失败任务重试。
- 系统分享/微信分享。

## P5：文档维护规则

- `context/project-context.md` 只保留当前事实和下一步，不写长历史。
- `docs/PRD.md` 记录产品边界和验收标准。
- `docs/TECH_DESIGN.md` 记录当前真实架构，不保留废弃 CLI 架构。
- `docs/TEST_CASES.md` 记录 Android App 测试，不保留 Python pytest 用例。
- 任何远端接口、登录策略、版本规则变化，都要同步更新以上文档。
