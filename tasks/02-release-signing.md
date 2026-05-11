# Task: 正式 Release 签名方案

## 背景

当前 `app/android/app/build.gradle.kts` 的 release 构建仍临时使用 debug signing：

```kotlin
release {
    // Keep debug signing for local release smoke tests until a product
    // release signing plan is explicitly provided.
    signingConfig = signingConfigs.getByName("debug")
}
```

这只适合本地 smoke test，不能用于正式分发或应用市场上架。

## 目标

建立正式 Android release signing 方案，确保 release APK/AAB 使用产品 keystore 签名，且密钥不进入 Git 仓库。

## 建议拆分

### 01. 生成/确认产品 keystore

- 明确 keystore 存放位置：本地安全目录或 CI secret。
- 明确 alias、store password、key password 管理方式。
- 禁止把 `.jks`、`.keystore`、密码文件提交到仓库。

### 02. Gradle signingConfig 改造

- Modify: `app/android/app/build.gradle.kts`
- 从环境变量或 `key.properties` 读取：
  - `storeFile`
  - `storePassword`
  - `keyAlias`
  - `keyPassword`
- release 缺少签名配置时应给出清晰错误或降级到本地 smoke-test 任务，不要静默产出伪正式包。

### 03. 文档与脚本

- Update: `scripts/build-release-apks.sh`
- Update: `README.md` / `app/README.md`
- 明确正式发包命令、签名前置条件、产物路径。

### 04. 验证

```bash
cd /tmp/zfj/apps/face-swap-video/app
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

并用 `apksigner verify` 验证签名信息。

## 暂不做

- 本任务只记录和设计正式签名方案；当前不生成真实 keystore，不提交密钥，不改变用户机器上的敏感配置。
