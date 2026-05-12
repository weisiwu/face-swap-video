# 方案 B：OSS + FC Serverless GPU + FaceFusion + ACR 推进计划

> 目标：不改动 Android 前端界面展示，使用阿里云 OSS 承载输入/输出文件，使用 ACR 托管 FaceFusion 自定义容器镜像，使用 FC Serverless GPU 运行现有 FaceFusion FastAPI 服务，并让 App 继续调用同一套 `/api/health`、`/api/swap/video/job`、`/api/swap/status/{jobId}`、`/api/swap/result/{jobId}` 协议。

## 0. 当前决策

- 方案 A（OSS + 阿里云 `MergeVideoFace`）因需要公司资质，当前暂停。
- 方案 B 改为自托管 FaceFusion：**不依赖 `MergeVideoFace` 资质**。
- 本阶段不需要 SLS：不创建日志服务 Project/Logstore，不把 SLS 作为前置条件。
- 本阶段不影响前端 UI：不改 `GenerationScreen`、按钮、弹框、结果页展示；如后续需要切换服务地址，也优先通过服务端域名或配置完成。
- 当前用户确认：第一阶段可以直接使用阿里云主账号凭证推进，不强制先创建 RAM 子账号。
- 当前用户确认：域名使用 FC 默认域名，不接入自定义域名 / DNS / 证书。

## 1. 目标架构

```text
Android App
  -> HTTPS API 域名
  -> FC Serverless GPU 自定义容器服务
       -> FastAPI 包装层：server/api/server.py
       -> FaceFusion CLI / Python 环境
       -> 临时工作目录 /tmp 或挂载存储
       -> OSS SDK 上传/下载输入输出
  -> OSS Bucket
       -> input/source images
       -> input/target videos
       -> output/result videos

ACR
  -> facefusion-fc-gpu:<tag>
  -> FC 使用该镜像启动 GPU 实例
```

## 2. 为什么可行

当前项目已经有一层 FastAPI 包装：

- `GET /api/health`
- `POST /api/swap/image`
- `POST /api/swap/video/job`
- `GET /api/swap/status/{jobId}`
- `GET /api/swap/result/{jobId}`

因此方案 B 优先复用 `server/api/server.py` 的 API 形状，只替换运行环境：

```text
macOS LaunchAgent + Cloudflare Tunnel
  -> FC Serverless GPU + ACR 镜像 + OSS 存储
```

App 前端不需要知道底层从本机 FaceFusion 变成 FC GPU。

## 3. 约束

1. **不改前端界面展示**
   - 不改生成页视觉；
   - 不改按钮文案；
   - 不改弹框；
   - 不改结果页布局。

2. **不使用 SLS**
   - FC 控制台如果默认提示日志服务，先选择不启用或跳过；
   - 第一阶段日志通过 FC 实例标准输出/控制台临时查看即可；
   - 后续只有排障确实需要时再单独讨论 SLS。

3. **优先最小闭环**
   - 先跑通 `health`；
   - 再跑通一条视频任务；
   - 再考虑并发、冷启动、成本、域名、鉴权和稳定性。

## 4. 我可以处理的事项

拿到必要账号和资源后，我可以处理：

1. 编写/调整 FaceFusion FC GPU 自定义容器 `Dockerfile`；
2. 编写 ACR build/push 脚本；
3. 编写 FC 服务/函数部署模板或控制台配置清单；
4. 把 `server/api/server.py` 调整为容器友好：
   - 端口从环境变量读取；
   - 输出目录走 `/tmp` 或 OSS；
   - GPU provider 改为 CUDA；
   - 支持 OSS 输入/输出路径；
5. 编写健康检查和端到端验证脚本；
6. 保持 Android 前端 UI 不变；
7. 补充单元测试，确保本地 FaceFusion API 兼容性不被破坏。

## 5. 需要用户处理/提供的前置事项

以下事项我无法代替用户在阿里云账号侧完成，需要用户提供或确认。

### 5.1 账号与计费

- 阿里云账号已实名认证；
- 已开通并允许付费使用：
  - 函数计算 FC；
  - FC Serverless GPU；
  - 容器镜像服务 ACR；
  - OSS 对象存储；
- 确认可用地域，建议优先选择同一区域部署 OSS、ACR、FC，减少跨区延迟和流量费。

### 5.2 FC Serverless GPU 资源

需要用户确认：

- 当前账号在目标地域是否有 FC GPU 使用权限；
- 可用 GPU 规格，例如 T4 / A10 / 其他阿里云 FC 支持规格；
- GPU 实例配额是否足够；
- 单实例最大执行时长是否满足视频处理，建议先按 5-15 分钟短视频验证；
- 是否允许配置预留实例或最小实例数，用于降低冷启动。

### 5.3 ACR

GitHub 已创建独立仓库用于存放 ACR / FC GPU 容器部署资产：

```text
https://github.com/weisiwu/facefusion-fc-gpu-acr
```

需要用户提供或确认阿里云 ACR 侧信息：

- ACR 实例类型：个人版/企业版均可，先以能被 FC 拉取为准；
- 命名空间，例如 `baoganai`；
- 镜像仓库名，例如 `facefusion-fc-gpu`；
- 镜像访问权限：FC 能拉取；
- 本机或 CI 能登录并 push 镜像。

建议环境变量：

```bash
ALIYUN_ACR_REGISTRY=registry.cn-shanghai.aliyuncs.com
ALIYUN_ACR_NAMESPACE=baoganai
ALIYUN_ACR_REPOSITORY=facefusion-fc-gpu
ALIYUN_ACR_USERNAME=...
ALIYUN_ACR_PASSWORD=***
```

当前用户已确认：

```bash
ALIYUN_ACR_REGISTRY=registry.cn-shanghai.aliyuncs.com
ALIYUN_ACR_NAMESPACE=baoganai
ALIYUN_ACR_REPOSITORY=facefusion-fc-gpu
```

### 5.4 OSS

需要用户创建或确认：

- OSS Bucket；
- Bucket 地域与 FC 同区；
- 生命周期规则：输入/输出文件 1-7 天自动清理；
- RAM/角色允许 FC 读写指定 Bucket；
- Object Key 使用英文/UUID，避免中文路径。

建议环境变量：

```bash
ALIYUN_OSS_BUCKET=baoganai-image-base
ALIYUN_OSS_ENDPOINT=oss-cn-beijing.aliyuncs.com
ALIYUN_REGION_ID=cn-beijing
```

当前用户已确认以上 OSS 配置。

注意：当前 OSS/目标地域是 `cn-beijing`，ACR 是 `cn-shanghai`。第一阶段可以先尝试，但建议确认 FC 在 `cn-beijing` 是否能稳定拉取上海 ACR 镜像；若遇到跨区拉取限制或冷启动慢，优先把 ACR 也建到 `cn-beijing`。

### 5.5 主账号凭证 / 权限

当前阶段用户确认：**直接使用主账号**，不强制先创建最小权限 RAM 用户或 RAM 角色。

注意：主账号权限较高，凭证只应配置在本机环境变量或本机私有 `.env` 中，不能写入代码、文档、git commit 或聊天明文输出。

如果后续切回更安全的 RAM 模式，最小权限方向：

- ACR：push/pull 指定镜像仓库；
- FC：创建/更新服务、函数、触发器、别名；
- OSS：读写指定 Bucket 前缀；
- VPC/NAS：如果后续启用，需要额外授权；第一阶段先不作为必需项。

建议环境变量：

```bash
ALIYUN_ACCESS_KEY_ID=...
ALIYUN_ACCESS_KEY_SECRET=...
ALIYUN_REGION_ID=cn-shanghai
```

### 5.6 域名与 HTTPS

当前阶段用户确认：**使用 FC 默认域名**。

因此第一阶段不需要：

- 自定义域名；
- DNS 切换；
- 证书托管；
- 替换现有 `facefusion.baoganai.com`。

若后续要替换线上 App 服务地址，再重新确认：

- 是否使用现有 `facefusion.baoganai.com`；
- DNS 是否可切换到 FC 自定义域名；
- 证书是否由阿里云托管或已有证书。

## 6. 第一阶段最小验证路径

```text
Step 1: 准备 ACR/FC 部署资产仓库
        - 仓库：github.com/weisiwu/facefusion-fc-gpu-acr
        - 资产：Dockerfile、build/push 脚本、FC custom-container 模板、health smoke test
Step 2: 本地构建 FaceFusion GPU 容器
Step 3: push 到 ACR
Step 4: FC 创建 GPU 自定义容器服务，不启用 SLS
Step 5: curl /api/health
Step 6: 用小视频 + 源人脸图走 /api/swap/video/job
Step 7: 轮询 /api/swap/status/{jobId}
Step 8: 下载 /api/swap/result/{jobId}
Step 9: 记录耗时、冷启动、费用、成功率、输出质量
```

## 7. 验证输出标准

| 字段 | 说明 |
|---|---|
| taskId | 本地任务 ID |
| imageTag | ACR 镜像 tag |
| fcService | FC 服务名 |
| fcFunction | FC 函数名 |
| gpuSpec | GPU 规格 |
| coldStartSeconds | 冷启动耗时 |
| uploadSeconds | 上传耗时 |
| processingSeconds | FaceFusion 处理耗时 |
| downloadSeconds | 下载耗时 |
| resultPath | 本地结果文件路径 |
| resultOssKey | OSS 结果 Key |
| status | completed / failed |
| error | 失败原因 |
| estimatedCost | 粗估费用 |

## 8. 成功标准

1. FC GPU 容器能启动并通过 `/api/health`；
2. FaceFusion 在 FC GPU 环境下能检测到 GPU/CUDA provider；
3. 短视频任务能完成并生成结果；
4. 输出质量不低于当前本机 FaceFusion preview 链路；
5. 单次耗时和冷启动可接受；
6. 不依赖 SLS；
7. 不改前端界面展示；
8. 成本和配额可控。

## 9. 15 秒视频 1 分钟优化目标（简化版）

详细任务见：`tasks/03-fc-gpu-15s-optimization.md`。

核心目标：15 秒单人脸视频尽量压到 1 分钟内完成，当前 preview 档位按 360p / 12fps / quality 50 处理，约 180 帧，目标平均处理速度不低于 3 FPS。

优先级：

1. 先做 15 秒视频端到端 benchmark，拆出冷启动、上传、预处理、检测、逐帧换脸、编码、下载耗时；
2. 确认真实 job 中 CUDA 没有 fallback 到 CPU；
3. Android 上传前压缩到 360p / 12fps / 15 秒以内，减少上传和服务端预处理；
4. 服务端对已达标视频跳过重复预处理；
5. 模型内置镜像并做启动预热，必要时测试 FC 预留实例；
6. 再做推理/编码优化：源脸缓存、目标脸检测降频、单主脸、关闭增强、尝试 NVENC；
7. OSS/网络优化：FC、OSS、ACR 同地域，后续可改 App 直传 OSS、结果回写 OSS。

阶段成功标准：

- P0：15 秒视频端到端 ≤ 180 秒；
- P1：15 秒视频端到端 ≤ 90 秒；
- P2：15 秒视频端到端 ≤ 60 秒；
- 60 秒单次成本约 ¥0.24-¥0.27 量级，主要成本来自 FC GPU 运行时长；
- 输出质量保持 preview 可接受水平。

暂不做：多段切片并行、大规模并发压测、改 Android 前端展示、开启 SLS、主动部署 dashboard/docs 站。

## 10. 暂不做事项

- 不改 Android 前端展示；
- 不接入 `MergeVideoFace`；
- 不开 SLS；
- 不做多租户复杂队列；
- 不做大规模并发压测；
- 不主动部署 dashboard/docs 站。
