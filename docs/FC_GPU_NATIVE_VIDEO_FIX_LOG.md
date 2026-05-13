# FC GPU 原生视频换脸问题修复记录

## 当前遇到的问题

项目目标是让 Android App 通过阿里云 FC Serverless GPU 调用 FaceFusion，完成**真实完整视频逐帧换脸**：

```text
目标视频每一帧 → 人脸检测/跟踪 → 源人脸逐帧替换 → 重新编码为 Android 可预览 MP4 → App 下载、预览、保存
```

当前 FC GPU 链路中，FaceFusion 的图片换脸能力可以工作，`/api/health` 也能看到 CUDA provider；但 FaceFusion 原生视频模式在 FC custom container 中不稳定：

- 视频 job 会进入 `processing / swapping_frame` 阶段；
- 进度常停在约 `85%`；
- 即使是极短视频或 1 帧 MP4，也可能长时间无输出；
- 最终会触发超时，例如 600 秒超时；
- 输出文件可能为 0 字节或不存在；
- Android 端表现为长时间处理中，或处理结束后无法获得可预览的真实视频结果。

此前为了验证“FC 服务可用、App 上传/下载链路可用、Android 是否能预览 H.264 MP4”，曾实现过 `FF_VIDEO_ENGINE=static_first_frame`：

```text
抽取/准备单帧 → 对单帧做 FaceFusion 图片换脸 → 用同一帧合成 MP4
```

该方案只能作为诊断/兜底链路，**不符合产品目标**，因为它不是完整视频逐帧换脸。自本记录开始，后续修复目标转向：

```text
路径 1：修通 FaceFusion 原生视频模式
```

除非另有明确说明，后续不再把 `static_first_frame` 作为主线目标。

## 成功标准

修复完成需同时满足：

1. FC GPU 上 FaceFusion 原生视频模式可稳定完成测试视频处理；
2. 处理结果不是 passthrough 原视频；
3. 输出视频包含真实逐帧换脸效果，而不是首帧静态合成；
4. 输出 MP4 可被 Android App 预览；
5. 结果视频满足基本兼容性：H.264/AVC、`yuv420p`、合理 duration/width/height、必要时 `faststart`；
6. 15 秒以内 preview 规格视频能在可接受时间内完成，阶段进度可观测；
7. 修复过程有可复现的 smoke 命令、jobId、日志和结果文件记录。

## 环境与当前已知事实

- 部署资产仓库：`/tmp/zfj/apps/facefusion-fc-gpu-acr`
- App/服务端主项目：`/tmp/zfj/apps/face-swap-video`
- FC 地域：`cn-shanghai`
- FC 默认公网域名：`https://facefus-gpu-api-ppxfvegpuf.cn-shanghai.fcapp.run`
- ACR 镜像仓库：`registry.cn-shanghai.aliyuncs.com/baoganai/facefusion-fc-gpu`
- 当前已部署镜像：`scheme-b-h264-preview-20260513003617`
- 当前该镜像配置仍包含：`FF_VIDEO_ENGINE=static_first_frame`，仅作为临时链路验证版本，不是最终目标。

## 修复记录

### 2026-05-13 记录初始化：停止首帧静态方案，转向原生视频模式

**采用方案**

- 停止继续把 `static_first_frame` 作为主线推进。
- 明确目标改为“路径 1：修通 FaceFusion 原生视频模式”。
- 建立本修复记录文档，用于后续每次修复追加记录：
  - 修改方案；
  - 修改范围；
  - 验证命令；
  - 修复结果；
  - 新发现问题；
  - 下一步行动。

**修复结果**

- 当前仅完成方向调整和记录文档初始化。
- 尚未开始新的原生视频模式代码修复。

**遇到的新问题 / 待调查点**

1. 需要复现并记录原生视频模式在 FC 上卡住的完整日志；
2. 需要确认卡住点在：
   - FaceFusion CLI `headless-run`；
   - FFmpeg/OpenCV 解码；
   - 视频编码；
   - CUDA/onnxruntime provider；
   - 模型加载或线程配置；
   - 容器文件系统/临时目录；
3. 需要新增或恢复一个 `native`/`facefusion_native` engine，避免与 `static_first_frame` 混淆；
4. 需要建立最小 smoke：health → image swap → native video 1 秒/1 帧 → native video 5 秒。

### 2026-05-13 依据《问题可能原因分析》收敛原生视频复现配置

**采用方案**

- 阅读 `/Users/weisiwu_clawbot_mac/Desktop/致富经/apps/face-swap-video/问题可能原因分析.md` 后，确认它对当前排查有直接帮助：
  - `85%` 是 `_track_facefusion_stage` 的合成进度上限，不是真实 FaceFusion 进度；
  - `FF_VIDEO_JOB_MODE=inline` 与视频 job API 的“提交后轮询”协议冲突，在 FC 网关 60s 单请求限制下会误导复现；
  - 原生视频应显式使用 `/tmp` 下 temp path，避免 FaceFusion 默认临时帧目录落到不可预期位置；
  - 应显式指定已打包进镜像的 detector/landmarker/swapper 模型，降低运行时下载导致卡死的概率；
  - debug 日志 tail 不能每 3 秒整文件读入内存。

**修改范围**

- 主项目 `server/api/server.py`：
  - 新增 `FF_FACE_DETECTOR_MODEL=yolo_face`、`FF_FACE_LANDMARKER_MODEL=2dfan4`、`FF_TEMP_PATH=/tmp/facefusion-temp`、`FF_VIDEO_MEMORY_STRATEGY=strict` 配置；
  - 原生视频 `headless-run` 参数增加 `--face-detector-model`、`--face-landmarker-model`、`--temp-path`、`--video-memory-strategy`；
  - 图片/静态 fallback 的 FaceFusion 调用也显式传 detector/landmarker；
  - `/api/health` 输出上述配置，并补充 `onnxruntime.get_device()` 诊断；
  - `_tail_file` 改为 seek 读取文件尾，避免 debug 日志变大后整文件读入内存。
- 部署资产仓库 `/tmp/zfj/apps/facefusion-fc-gpu-acr`：
  - `Dockerfile`、`templates/s.yaml`、`docker/start_server.sh` 统一为 `FF_VIDEO_ENGINE=facefusion`、`FF_VIDEO_JOB_MODE=background`；
  - 统一设置 detector/landmarker、`FF_TEMP_PATH=/tmp/facefusion-temp`、`FF_VIDEO_MEMORY_STRATEGY=strict`；
  - 将 `OMP/OPENBLAS/MKL_NUM_THREADS` 从 1 提到 2，缓解视频预/后处理完全单线程；
  - 容器启动时创建并打印 temp path。
- 已停止一个正在构建但配置仍含 inline 风险的旧镜像构建进程，避免继续推送错误复现镜像。

**验证命令**

```bash
cd /tmp/zfj/apps/facefusion-fc-gpu-acr
bash -n scripts/build_and_push.sh docker/start_server.sh
python3 -m py_compile scripts/smoke_health.py scripts/smoke_video_job.py
python3 -m py_compile /tmp/zfj/apps/face-swap-video/server/api/server.py
python3 -m pytest /tmp/zfj/apps/face-swap-video/server/api/test_api_server_config.py -q
```

**修复结果**

- 本地静态验证通过：`10 passed in 0.33s`。
- 这一步尚未证明 FC GPU 原生视频已经修通；它先修正了复现配置，避免 inline/job 模式错误、默认 temp 目录和运行时模型选择干扰根因定位。

**遇到的新问题**

- 当前尚未重新构建/部署新镜像验证 FC health、image swap、1 帧/短视频 native job。
- `JOBS` 仍是进程内存状态，后续若需要跨实例/实例冻结鲁棒性，仍需外部化到 OSS/Redis/磁盘清单。
- `/api/health` 的 `onnxruntime.get_device()` 只能辅助判断设备类型，仍不能完全证明具体模型 session 在 CUDA 上成功执行；后续应在 FC 容器内补一次真实 ONNX session 诊断。

**下一步**

- 用修正后的配置重新构建并推送 native 镜像；
- 部署到 FC 后按 health → image swap → 1 帧 video job → 5 秒 video job 顺序复现；
- 抓取新 job 的 stdout/stderr tail、status payload 和输出文件增长情况，再进入根因确认。

### 2026-05-13 1帧原生视频复现仍超时，加入 Python 栈转储诊断

**采用方案**

- 使用新镜像 `native-facefusion-bg-20260513012323` 完成 FC 部署后，按最小链路验证：health → image swap → 1 帧 native video。
- 1 帧 native video 仍在 FaceFusion 子进程内超时，因此下一步不继续猜修复，而是给 FaceFusion 子进程加入 `faulthandler` 栈转储：
  - 通过 Python wrapper 启动 `facefusion.py headless-run`；
  - 注册 `SIGUSR1`；
  - 超时前先向 FaceFusion 进程组发送 `SIGUSR1`，把所有 Python 线程栈写入 stderr，再终止进程。

**验证结果**

- health 通过，关键配置生效：`video_engine=facefusion`、`video_job_mode=background`、`temp_path=/tmp/facefusion-temp`、`onnxruntime_device=GPU`。
- `/api/swap/image` 图片换脸通过：HTTP 200，约 29 秒，输出 JPEG 33101 bytes。
- 1 帧 H.264 native video job 失败：
  - jobId：`3676aec0edad4c008e89b82621e75a3b`
  - target：1 frame / 1s / h264 / 192x352 / 13567 bytes
  - FaceFusion 命令已确认包含：`--face-detector-model yolo_face`、`--face-landmarker-model 2dfan4`、`--temp-path /tmp/facefusion-temp`、`--video-memory-strategy strict`
  - 结果：600 秒超时，`facefusion_output_bytes=0`
  - stderr 仅有 OpenBLAS L2 cache warning，无 FaceFusion 进度输出。

**修改范围**

- `server/api/server.py`：
  - `_run_facefusion()` 改为通过 wrapper 执行 FaceFusion，并启用 `faulthandler`；
  - 超时处理在 kill 前发送 `SIGUSR1`，用于抓取 Python 线程栈，帮助定位卡在下载、导入、视频抽帧、模型 session 创建还是逐帧处理。

**验证命令**

```bash
cd /tmp/zfj/apps/facefusion-fc-gpu-acr
python3 -m py_compile /tmp/zfj/apps/face-swap-video/server/api/server.py
python3 -m pytest /tmp/zfj/apps/face-swap-video/server/api/test_api_server_config.py -q
bash -n scripts/build_and_push.sh docker/start_server.sh
python3 -m py_compile scripts/smoke_health.py scripts/smoke_video_job.py
```

**修复结果**

- 本地静态验证通过：`10 passed in 0.73s`。
- 当前还不是最终修复；这是为下一轮 FC 复现增加根因观测能力。

**下一步**

- 构建并部署带 `faulthandler` 的诊断镜像；
- 再跑 1 帧 native video job；
- 读取失败 status 中的 `facefusion_stderr_tail`，用 Python 栈判断真实卡点。

### 2026-05-13 调整为 FC 稳态 OSS Job 架构

**采用方案**

- 继续当前阿里云 FC Serverless GPU 方案，但不再依赖单实例进程内存保存视频 job 状态。
- 架构改为 OSS 外部化：输入文件、`status.json`、FaceFusion stdout/stderr/faulthandler 日志、结果 MP4 都以 `jobs/{job_id}/...` 结构写入 OSS。
- `/api/swap/status/{job_id}` 和 `/api/swap/result/{job_id}` 保留现有 Android 协议，优先读内存/本地，缺失时回退 OSS，避免 FC 实例切换后直接 404。
- 详细实施计划已写入：`tasks/04-fc-stable-oss-job-architecture.md`。

**修改范围**

- 新增任务文件：`tasks/04-fc-stable-oss-job-architecture.md`。
- 当前尚未改生产代码；下一步按 TDD 从 `JobStore` 抽象开始实现。

**验证命令**

```bash
cd /tmp/zfj/apps/face-swap-video
python3 -m pytest server/api/test_job_store.py server/api/test_api_server_config.py -q
python3 -m py_compile server/api/server.py server/api/job_store.py
```

**修复结果**

- 已完成架构方向收敛和实施任务拆分。
- 本地 API native video 已验证 1 帧和 5 秒原生视频成功，后续以该本地成功链路作为 FC 改造前基线。

**遇到的新问题**

- 本地 Docker Linux 诊断镜像仍在构建 CUDA base image，尚未完成容器内复现。
- FC 侧 CUDA 卡住根因仍需依赖外部化日志/栈进一步确认。

**下一步**

- 先实现 `JobStore` 本地/OSS 抽象和状态回退测试；
- 再接入视频 job 输入、状态、日志、结果上传；
- 本地验证通过后再构建部署 FC。

### 2026-05-13 实现 OSS JobStore 与跨实例结果恢复

**采用方案**

- 保持 Android App 现有接口协议不变：`/api/swap/video/job`、`/api/swap/status/{job_id}`、`/api/swap/result/{job_id}`。
- 服务端新增可插拔 `JobStore`：默认关闭；本地测试用 `LOCAL_JOB_STORE_DIR`；FC 生产用 OSS。
- `JOBS` 内存仍作为同实例快速路径；当内存缺失时，`status` 从外部 `status.json` 恢复。
- 完成时将结果 MP4 上传为 `output/result.mp4`，`result` 接口在本地文件丢失/跨实例时回退外部存储读取。
- FaceFusion stdout/stderr 日志完成时上传到 `logs/`，便于 FC 失败后追溯。

**修改范围**

- 主项目 `/tmp/zfj/apps/face-swap-video`：
  - 新增 `server/api/job_store.py`：`DisabledJobStore`、`LocalJobStore`、`OssJobStore`、`create_job_store_from_env()`。
  - 新增 `server/api/test_job_store.py`：覆盖本地 store、OSS fake bucket、env 初始化。
  - 修改 `server/api/server.py`：
    - 初始化 `JOB_STORE`；
    - `_set_job()` 写内存后同步外部状态；
    - `_get_job()` 支持外部状态回填；
    - 视频 job 保存输入 `source_key/target_key`、结果 `output_key`、日志 key；
    - `swap_result()` 本地文件缺失时从 job store 返回 `video/mp4` bytes；
    - `health/status` 返回 job store 诊断字段。
  - 修改 `server/api/test_api_server_config.py`：覆盖内存丢失后 status 恢复、结果文件丢失后 result 恢复。
- 部署资产 `/tmp/zfj/apps/facefusion-fc-gpu-acr`：
  - `templates/s.yaml` 增加 `OSS_JOB_STORE_ENABLED=1`、`OSS_JOB_PREFIX`、OSS 访问凭证环境变量透传；
  - `Dockerfile` 针对本机 ARM64 诊断构建改为安装 CPU `onnxruntime`，amd64/FC GPU 仍安装 `onnxruntime-gpu`。

**验证命令**

```bash
cd /tmp/zfj/apps/face-swap-video
python3 -m py_compile server/api/server.py server/api/job_store.py
python3 -m pytest server/api/test_api_server_config.py server/api/test_job_store.py -q

cd /tmp/zfj/apps/facefusion-fc-gpu-acr
bash -n scripts/build_and_push.sh docker/start_server.sh
python3 - <<'PY'
import yaml
from pathlib import Path
print(yaml.safe_load(Path('templates/s.yaml').read_text())['resources']['facefusionApi']['props']['environmentVariables']['OSS_JOB_STORE_ENABLED'])
PY
```

**修复结果**

- 主项目验证通过：`18 passed in 2.28s`。
- 部署模板验证通过，输出 `OSS_JOB_STORE_ENABLED=1`。
- 旧本地 ARM64 Docker 诊断构建失败根因已确认：`onnxruntime-gpu==1.23.2` 没有 ARM64 wheel；已改为按架构条件安装。

**遇到的新问题**

- 新 ARM64 本地诊断镜像仍在构建中，需等待结果确认 Dockerfile 条件安装是否完全修复。
- 尚未重新构建并推送 FC amd64 GPU 镜像，未完成云端 App 端到端验证。

**下一步**

- 等待本地 ARM64 诊断镜像构建完成；
- 成功后构建/推送 amd64 GPU 镜像并部署 FC；
- 重新跑 health → image swap → 1 帧 video → 5 秒 video；
- 验证 Android App 指向 FC 默认域名后可处理并预览视频结果。

### 2026-05-13 本地 Linux 容器原生视频基线验证通过，补充无效预处理回退

**采用方案**

- 在本地 ARM64 Docker Linux 诊断容器中挂载最新 `server/api/server.py` / `job_store.py`，继续验证 FaceFusion 原生视频模式，而不是静态首帧方案。
- 针对 1 帧 MP4 复现出的新问题，新增预处理输出有效性校验：ffmpeg 预处理产物即使非 0 字节，也必须能被 `ffprobe` 读出正数 width/height；否则删除预处理产物并回退原 target，避免 FaceFusion 因 `detect_video_resolution()` 返回 None 或无可抽帧帧而提前崩溃。
- 使用 5 秒测试素材建立本地 Linux 容器基线：FaceFusion `headless-run` 对视频逐帧处理并输出 MP4。

**修改范围**

- 主项目 `/tmp/zfj/apps/face-swap-video`：
  - `server/api/server.py`：新增 `_video_has_readable_resolution()`，并在 `_preprocess_target_video()` 中校验优化视频是否可读；不可读时安全回退原视频。
  - `server/api/test_api_server_config.py`：新增 `test_preprocess_falls_back_when_optimized_video_has_no_readable_resolution`。

**验证命令**

```bash
cd /tmp/zfj/apps/face-swap-video
python3 -m pytest server/api/test_api_server_config.py::test_preprocess_falls_back_when_optimized_video_has_no_readable_resolution -q
python3 -m pytest server/api/test_api_server_config.py server/api/test_job_store.py -q
python3 -m py_compile server/api/server.py server/api/job_store.py

cd /tmp/zfj/apps/facefusion-fc-gpu-acr
docker run --rm -p 19000:9000 --name facefusion-local-diagnostic-fixed \
  -e API_PORT=9000 \
  -e FF_EXECUTION_PROVIDERS=cpu \
  -e FF_FACEFUSION_TIMEOUT_SECONDS=300 \
  -e OSS_JOB_STORE_ENABLED=local \
  -e LOCAL_JOB_STORE_DIR=/tmp/facefusion-job-store \
  -v /tmp/zfj/apps/face-swap-video/server/api/server.py:/opt/facefusion/server/api/server.py:ro \
  -v /tmp/zfj/apps/face-swap-video/server/api/job_store.py:/opt/facefusion/server/api/job_store.py:ro \
  facefusion-local-diagnostic:cpu-arm64-fixed

python3 scripts/smoke_video_job.py http://127.0.0.1:19000 \
  --source /tmp/zfj/apps/face-swap-video/materials/one-person-source.jpg \
  --target /tmp/zfj/apps/face-swap-video/materials/one-person-5s-source.mp4 \
  --output /tmp/zfj/apps/face-swap-video/.tmp-smoke/local-container-5s-result-fixed2.mp4 \
  --poll-timeout 420 --poll-interval 10
```

**修复结果**

- 单测/静态验证通过：`19 passed in 0.37s`。
- 本地 Linux 容器 5 秒原生视频 job 完成：
  - jobId：`30972f8809cb431097b2056f176ecaba`
  - 总耗时：约 `60.85s`
  - 服务端处理耗时：约 `55.619s`
  - FaceFusion stderr 显示 `processing: ... 58/60`，证明进入了逐帧处理而不是静态首帧合成。
  - 输出文件：`.tmp-smoke/local-container-5s-result-fixed2.mp4`
  - 结果 MP4：H.264，`192x352`，`12fps`，`60` 帧，`5.000000s`。
  - result sha256：`c49d0fe61f163ef6e84157f4ba4e8b44f98b63080332967b209e61e953e3424f`
  - target sha256：`c143e3e1ec21aee269820a6d290a89c7f51c63aa0d70966c10d9b13ad4769828`
  - result 与 target hash 不同，排除 passthrough。

**遇到的新问题**

- 1 帧 MP4 仍可能失败：FaceFusion 日志显示 `extracting: 0frame` 与 `temporary frames not found`。该问题更像超短视频/帧抽取边界问题，不影响 5 秒真实视频基线；后续如果继续保留 1 帧 smoke，应改成 1 秒以上、可抽到多帧的视频，或把 1 帧场景标记为兼容性边界用例。
- 本地 ARM64 重新完整 Docker build 仍可能因 pip 下载耗时超过 600s；当前通过挂载最新 server 文件复用既有诊断镜像完成基线验证。

**下一步**

- 使用当前 JobStore + 预处理回退修复重新构建并推送 amd64 GPU 镜像；
- 部署到 FC 后重新验证 health → image swap → 5 秒原生视频 job；
- 只有 FC 5 秒 native job completed 且 result 与 target hash 不同后，再继续 Android APK 指向 FC 默认域名的预览验证。

## 后续记录模板

### YYYY-MM-DD 修复标题

**采用方案**

- 

**修改范围**

- 

**验证命令**

```bash

```

**修复结果**

- 

**遇到的新问题**

- 

**下一步**

- 
