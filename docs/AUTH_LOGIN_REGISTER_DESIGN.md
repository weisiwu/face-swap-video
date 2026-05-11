# 手机号验证码登录注册设计方案

> 当前实现状态：Mock 手机号验证码登录。用户启动后直接进入生成页，可先选择素材；只有点击“生成/一键开始换脸”时才要求登录。本文档已按当前产品决策清理，废弃“启动页后强制登录”的旧方案。

## 1. 当前目标

在不打断生成主流程的前提下，为后续任务归属、生成记录、额度/会员能力预留登录入口。

当前阶段只做轻量登录闭环：

- 生成页保留为 App 主入口。
- 未登录用户可以浏览页面并选择素材。
- 点击生成时如未登录，则进入登录页。
- 登录成功后返回生成页，再继续生成操作。
- 当前不接真实短信，不做 token 持久化。

## 2. 当前用户流程

### 2.1 首次打开 App

```text
启动页
  ↓
生成页
  ↓
选择源人脸 + 目标素材
  ↓
点击生成
  ├─ 已登录 → 直接提交远端任务
  └─ 未登录 → LoginScreen → 登录成功返回生成页
```

### 2.2 Mock 手机号验证码登录

```text
输入手机号
  ↓
点击获取验证码（Mock，仅倒计时）
  ↓
输入 6 位数字验证码
  ↓
点击登录/注册
  ↓
AuthProvider 设置内存登录态
  ↓
返回生成页
```

## 3. 已实现模块

| 模块 | 文件 | 状态 |
|---|---|---|
| Auth 状态 | `app/lib/features/auth/providers/auth_provider.dart` | 已实现 Mock 登录、验证码倒计时、退出登录 |
| 登录页 | `app/lib/features/auth/screens/login_screen.dart` | 已实现手机号/验证码输入、协议链接、主卡手机号回填 |
| 路由入口 | `app/lib/features/auth/screens/auth_gate.dart` | 当前默认进入生成页 |
| 主流程集成 | `app/lib/features/generation/screens/generation_screen.dart` | 未登录点击生成跳转登录页；顶部账号入口 |
| 主卡手机号 | `app/lib/features/auth/services/device_phone_service.dart` | 在用户主动点击后尝试读取 Android 主卡手机号 |
| 测试 | `app/test/auth_provider_test.dart` | 已覆盖主要 Mock 状态 |

## 4. 当前行为约束

- 不再采用“启动页后未登录进入登录页”的强制登录策略。
- 不因为登录功能重排 `GenerationScreen` 主流程。
- 登录页只服务于生成动作，不作为 App 首页。
- 长按生成页账号入口可退出登录，用于测试和轻量账号控制。
- 当前登录态为内存态，重启 App 后会恢复未登录。

## 5. 后续真实 Auth API 设计

当后端账号服务准备好后，再新增独立 `AuthApiService`：

```text
POST /auth/sms/send
POST /auth/sms/login
GET  /auth/me
POST /auth/refresh
POST /auth/logout
POST /auth/account/delete
```

原则：

- App 不直连短信服务商，只请求自有后端。
- Auth API 与 FaceFusion 生成 API 解耦，不塞进 `ApiService`。
- 登录成功后保存 `accessToken` / `refreshToken` / user 信息。
- 业务接口需要任务归属时，再统一带 `Authorization: Bearer <token>`。

## 6. 后续本地登录态

MVP 可选：

- `shared_preferences`：实现简单，适合非敏感 demo。
- `flutter_secure_storage`：更适合正式商业化、会员、支付等场景。

建议正式接真实短信时直接评估 `flutter_secure_storage`。

## 7. 页面设计

`LoginScreen` 保持轻量：

```text
[Logo]
视频换脸
登录后继续生成

[手机号输入框]
[验证码输入框] [获取验证码 / 60s]

[ ] 我已阅读并同意《用户协议》和《隐私政策》

[登录 / 注册]
说明：未注册手机号将自动创建账号
```

协议链接：

- 隐私政策：`https://baoganai.com/privacy`
- 用户协议：`https://baoganai.com/terms`

## 8. 测试策略

### 当前阶段

- `AuthProvider.sendCode()`：手机号非空、倒计时、防重复发送。
- `AuthProvider.loginWithSms()`：手机号非空、验证码非空、验证码 6 位数字、登录态置为已登录。
- `logout()`：清理登录态。
- Widget：未登录点击生成进入登录页；登录成功后可回到生成页。

### 接真实后端后

- Auth API 成功/失败响应解析。
- token 持久化与恢复。
- token 过期 refresh。
- 退出登录清理本地存储。
- 生成任务带 token 与服务端绑定 userId。

## 9. 暂不做

- 微信登录。
- 会员/额度。
- 我的生成记录。
- 完整个人中心。
- 账号合并。
- App 内 WebView 协议页。
