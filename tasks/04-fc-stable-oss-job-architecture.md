# FC 稳态 OSS Job 架构实施计划

> 目标：继续使用阿里云 FC Serverless GPU，但把视频任务从“进程内存 job + 本地临时结果”改成更稳的 OSS 外部化架构，降低实例重启/冻结/切换导致 job 丢失的问题，并让失败日志可追溯。

## 背景

当前 FC 链路已经验证：

- 本地 FaceFusion 原生视频 `headless-run` 可跑通；
- 本地 API native video job 可跑通 1 帧与 5 秒视频；
- FC 上图片换脸可用，但原生视频 job 可能 600s 超时，且日志不足；
- 当前 job 状态保存在 FC 实例内存中，实例重启/部署/切换会导致 `/api/swap/status/{jobId}` 返回 404；
- 当前输出结果主要依赖 FC 本地 `/tmp/facefusion-output`，不适合跨实例或长任务追踪。

## 新架构

```text
Android App / smoke 脚本
  -> POST /api/swap/video/job 上传 source/target
  -> FC 将 source/target 保存到 OSS jobs/{job_id}/input/
  -> FC 将 job 状态写入 OSS jobs/{job_id}/status.json
  -> FaceFusion 子进程在 /tmp/jobs/{job_id}/work 处理
  -> stdout/stderr/faulthandler dump 写入 OSS jobs/{job_id}/logs/
  -> 结果 MP4 写入 OSS jobs/{job_id}/output/result.mp4
  -> GET /api/swap/status/{job_id} 优先读内存，缺失时回退 OSS status.json
  -> GET /api/swap/result/{job_id} 优先本地文件，缺失时从 OSS 下载/流式返回
```

## 成功标准

1. `POST /api/swap/video/job` 后，OSS 中存在：
   - `jobs/{job_id}/input/source.jpg`
   - `jobs/{job_id}/input/target.mp4`
   - `jobs/{job_id}/status.json`
2. `/api/swap/status/{job_id}` 在进程内存丢失后仍可通过 OSS 状态返回，不再直接 404；
3. 失败时 OSS 中存在 stderr/stdout tail 或完整日志，包含 FaceFusion 命令、超时、faulthandler 栈；
4. 成功时 OSS 中存在 `jobs/{job_id}/output/result.mp4`；
5. `/api/swap/result/{job_id}` 可从 OSS 回退下载结果；
6. 本地测试覆盖：OSS disabled 保持旧行为；OSS enabled 使用 fake/local store 验证状态持久化；
7. FC 部署前，本地 API native video 仍能跑通。

## 任务拆分

### Task 1：抽象 JobStore

**文件：**

- 新增：`server/api/job_store.py`
- 新增测试：`server/api/test_job_store.py`

**内容：**

- 定义 `JobStore` 协议/基类；
- 实现 `LocalJobStore`，将 job 状态、输入、输出、日志写入本地目录，便于本地测试；
- 预留 `OssJobStore` 接口，但先不强耦合业务代码。

**验证：**

```bash
cd /tmp/zfj/apps/face-swap-video
python3 -m pytest server/api/test_job_store.py -q
```

### Task 2：接入 OSS JobStore

**文件：**

- 修改：`server/api/job_store.py`
- 修改：`server/api/test_job_store.py`
- 修改：`server/api/server.py`

**环境变量：**

```text
OSS_JOB_STORE_ENABLED=1
ALIYUN_OSS_BUCKET=...
ALIYUN_OSS_ENDPOINT=...
ALIYUN_ACCESS_KEY_ID=...
ALIYUN_ACCESS_KEY_SECRET=...
OSS_JOB_PREFIX=face-swap-video/jobs
```

**内容：**

- 实现 `OssJobStore`：上传输入、状态、日志、结果；
- 缺少 OSS 环境变量时自动降级为 disabled，不影响本地开发；
- `/api/health` 增加 job store 配置摘要，不泄漏密钥。

**验证：**

```bash
python3 -m pytest server/api/test_job_store.py server/api/test_api_server_config.py -q
python3 -m py_compile server/api/server.py server/api/job_store.py
```

### Task 3：状态接口 OSS 回退

**文件：**

- 修改：`server/api/server.py`
- 修改/新增测试：`server/api/test_api_server_config.py` 或 `server/api/test_api_job_status.py`

**内容：**

- `_set_job()` 每次更新状态时同步写 `status.json`；
- `/api/swap/status/{job_id}` 内存不存在时尝试从 JobStore 读取；
- 仅当内存和 JobStore 都不存在时返回 404；
- status payload 增加 `status_persisted` / `job_store` 诊断字段。

**验证：**

```bash
python3 -m pytest server/api/test_api_server_config.py -q
```

### Task 4：结果接口 OSS 回退

**文件：**

- 修改：`server/api/server.py`
- 修改/新增测试：`server/api/test_api_result.py`

**内容：**

- FaceFusion 成功后将 result MP4 上传到 JobStore；
- `/api/swap/result/{job_id}` 本地结果不存在时，从 JobStore 拉取到 `/tmp` 再返回；
- status 中记录 `result_oss_key`、`result_bytes`。

**验证：**

```bash
python3 -m pytest server/api/test_api_server_config.py -q
```

### Task 5：日志与 faulthandler dump 外部化

**文件：**

- 修改：`server/api/server.py`
- 修改测试：`server/api/test_api_server_config.py`

**内容：**

- `_run_facefusion()` 结束/超时时上传 stdout/stderr 日志；
- 超时前发送 `SIGUSR1` 抓栈后，再上传 stderr；
- status 中记录 `facefusion_stdout_key`、`facefusion_stderr_key`；
- 失败 error 中只保留 tail，完整日志走 OSS。

**验证：**

```bash
python3 -m pytest server/api/test_api_server_config.py -q
```

### Task 6：部署资产同步

**文件：**

- 修改：`/tmp/zfj/apps/facefusion-fc-gpu-acr/templates/s.yaml`
- 修改：`/tmp/zfj/apps/facefusion-fc-gpu-acr/README.md`
- 必要时修改：`/tmp/zfj/apps/facefusion-fc-gpu-acr/scripts/smoke_video_job.py`

**内容：**

- FC 模板加入非敏感 job store env；
- 敏感 AK 仍从本地 `.env` / Serverless Devs env 注入，不写入文档明文；
- smoke 脚本输出 status 中的 job store 字段和日志 key。

**验证：**

```bash
cd /tmp/zfj/apps/facefusion-fc-gpu-acr
bash -n scripts/build_and_push.sh docker/start_server.sh
python3 -m py_compile scripts/smoke_health.py scripts/smoke_video_job.py
```

### Task 7：本地与 FC 验证

**本地：**

```bash
cd /tmp/zfj/apps/facefusion-fc-gpu-acr
python3 scripts/smoke_video_job.py http://127.0.0.1:9998 \
  --source /tmp/zfj/apps/face-swap-video/materials/one-person-source.jpg \
  --target .build/one-frame-target.mp4 \
  --output .build/local-stable-oss-one-frame.mp4
```

**FC：**

```bash
BASE=https://facefus-gpu-api-ppxfvegpuf.cn-shanghai.fcapp.run
python3 scripts/smoke_health.py "$BASE"
python3 scripts/smoke_video_job.py "$BASE" \
  --source /tmp/zfj/apps/face-swap-video/materials/one-person-source.jpg \
  --target .build/one-frame-target.mp4 \
  --output .build/fc-stable-oss-one-frame.mp4 \
  --poll-timeout 900
```

**验收：**

- 成功：下载结果，sha256 不同于 target，ffprobe 显示 H.264/yuv420p；
- 失败：能从 OSS 找到完整日志和 faulthandler 栈，不再只有 OpenBLAS warning。

## 暂不做

- 暂不改 Android 前端 UI；
- 暂不做 App 直传 OSS；
- 暂不引入 Redis/数据库；
- 暂不做多 worker/切片并行；
- 暂不把 `static_first_frame` 作为主线。
