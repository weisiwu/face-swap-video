# Task: 手机号验证码登录注册收口

> 对应设计文档：`docs/AUTH_LOGIN_REGISTER_DESIGN.md`
> 当前产品决策：启动页后直接进入生成页；未登录用户可以先选择素材，只有点击“生成/一键开始换脸”时才进入登录页。

## 当前事实

已实现：

- `app/lib/features/auth/providers/auth_provider.dart`：Mock 手机号验证码登录、60 秒倒计时、退出登录。
- `app/lib/features/auth/screens/login_screen.dart`：手机号/验证码输入、协议链接、主卡手机号回填。
- `app/lib/features/auth/screens/auth_gate.dart`：当前默认进入生成页。
- `app/lib/features/generation/screens/generation_screen.dart`：未登录点击生成跳转登录页；顶部轻量账号入口。
- `app/test/auth_provider_test.dart`：覆盖主要 Mock 状态。

尚未实现（必须作为后续 TODO，不可误认为已经具备真实账号体系）：

- 真实短信 API。
- token 本地持久化。
- token refresh / logout / account delete。
- 生成任务与 userId 绑定。
- 生成记录/会员/额度。

当前 Mock 只用于打通登录触发、返回生成页、协议勾选和倒计时体验；不具备真实验证码校验、账号安全、跨端登录态或服务端用户归属能力。

## 目标

把当前 Mock 登录收口为可继续演进的真实账号体系，但不改变主流程、不强制启动登录。

## 建议任务拆分

### 01. Auth 校验工具收口

- Create/Modify: `app/lib/features/auth/utils/auth_validators.dart`
- Test: `app/test/auth_validators_test.dart`

验收：

- 手机号非空校验。
- 验证码 6 位数字校验。
- LoginScreen 与 AuthProvider 复用同一套校验逻辑。

### 02. AuthApiService 接口层

- Create: `app/lib/features/auth/services/auth_api_service.dart`
- Test: `app/test/auth_api_service_test.dart`

接口预留：

```text
POST /auth/sms/send
POST /auth/sms/login
GET  /auth/me
POST /auth/refresh
POST /auth/logout
POST /auth/account/delete
```

原则：Auth 服务与 FaceFusion `ApiService` 解耦。

### 03. 本地登录态存储

- Create: `app/lib/features/auth/services/auth_storage.dart`
- Test: `app/test/auth_storage_test.dart`
- Evaluate dependency: `shared_preferences` 或 `flutter_secure_storage`

验收：

- 保存 accessToken、refreshToken、user 信息。
- 重启 App 可恢复登录态。
- logout 清理本地状态。

### 04. AuthProvider 接真实接口

- Modify: `app/lib/features/auth/providers/auth_provider.dart`
- Test: `app/test/auth_provider_test.dart`

验收：

- 无 token 初始化为 unauthenticated。
- token 有效初始化为 authenticated。
- 发送验证码调用 Auth API。
- 登录成功保存 token 与用户信息。
- 登录失败保留错误信息，不污染旧状态。
- token 过期可 refresh，refresh 失败回到未登录。

### 05. 登录触发与返回体验

- Modify: `app/lib/features/generation/screens/generation_screen.dart`
- Modify: `app/lib/features/auth/screens/login_screen.dart`
- Test: `app/test/widget_test.dart`

验收：

- 启动页后未登录仍直接进入生成页。
- 未登录选择完整素材后点击生成，进入登录页。
- 登录成功后返回生成页，并保留已选择素材。
- 用户可再次点击生成继续提交。
- 不移动原有素材卡片、合规提示、吸底按钮、版本号。

### 06. 生成任务归属

当前不做，等后端确认后再接：

- 生成 API 请求带 `Authorization: Bearer <token>`。
- 服务端把 jobId 绑定到 userId。
- 为“我的生成记录”预留数据结构。

## 暂不做

- 启动强制登录。
- 微信登录。
- 会员/额度。
- 我的生成记录。
- 完整个人中心。
- 账号合并。
- App 内 WebView 协议页。

## 全量验证

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
flutter test
flutter build apk --debug
```
