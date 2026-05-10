# 技术方案设计：face-swap-video

## 1. 总体架构

```text
CLI / GUI
  ↓
Config Loader
  ↓
Safety Gate（授权/水印/审计）
  ↓
Video IO（抽帧/合成）
  ↓
Face Detection（检测）
  ↓
Face Tracking（轨迹）
  ↓
Face Swap Engine（换脸）
  ↓
Post Process（水印/修复/编码）
  ↓
Report & Manifest
```

## 2. 推荐技术栈

| 模块 | MVP | 后续可选 |
|---|---|---|
| CLI | argparse / typer | Typer + Rich |
| 配置 | dataclass + JSON | pydantic |
| 视频处理 | OpenCV / ffmpeg | PyAV |
| 人脸检测 | InsightFace / RetinaFace | MediaPipe / YOLO-face |
| 人脸关键点 | InsightFace | 3DDFA |
| 换脸模型 | 接口预留 | inswapper / SimSwap / FaceFusion 兼容层 |
| 水印 | OpenCV 绘制 | ffmpeg filter / C2PA 元数据 |
| 测试 | pytest | 合成视频测试 |

## 3. 模块设计

### 3.1 Safety Gate

文件：`src/face_swap_video/safety.py`

职责：

- 读取 `consent_manifest.json`；
- 校验 `source_face` 与 `target_video` 是否在授权范围内；
- 校验输出是否启用水印；
- 生成审计字段。

### 3.2 Config

文件：`src/face_swap_video/config.py`

职责：

- 定义 `PipelineConfig`；
- 支持 JSON 读取；
- 校验路径、输出目录、水印策略。

### 3.3 Pipeline

文件：`src/face_swap_video/pipeline.py`

职责：

- 编排授权校验、视频处理、人脸检测、换脸、输出报告；
- MVP 阶段先提供接口和 dry-run；
- 后续逐步接入真实模型。

### 3.4 CLI

文件：`src/face_swap_video/cli.py`

职责：

- `--config` 指定配置文件；
- `--dry-run` 仅验证配置和授权；
- 输出清晰的成功/失败信息。

## 4. 数据结构

### 4.1 consent_manifest.json

```json
{
  "project": "demo",
  "operator": "weisiwu",
  "source_faces": [
    {
      "path": "assets/source/person_a.jpg",
      "subject": "person_a",
      "consent_type": "explicit",
      "allowed_use": ["face_swap_test", "internal_preview"],
      "expires_at": "2026-12-31"
    }
  ],
  "target_videos": [
    {
      "path": "assets/input/video.mp4",
      "allowed_use": ["face_swap_test", "internal_preview"]
    }
  ]
}
```

### 4.2 pipeline_config.json

```json
{
  "source_face": "assets/source/person_a.jpg",
  "target_video": "assets/input/video.mp4",
  "output_dir": "outputs/demo",
  "consent_manifest": "consent_manifest.json",
  "watermark_text": "AI-generated / authorized face swap",
  "dry_run": true
}
```

## 5. MVP 实现策略

第一阶段只做“安全可运行骨架”：

1. 完成配置与授权校验；
2. CLI dry-run 可运行；
3. 输出 run manifest；
4. 用 stub pipeline 占位模型调用；
5. 单元测试覆盖安全边界。

第二阶段接入人脸检测：

1. OpenCV 抽帧；
2. InsightFace 检测；
3. 保存检测框和关键帧；
4. 人脸轨迹初版。

第三阶段接入换脸引擎：

1. 兼容开源换脸模型；
2. 支持单人脸轨迹替换；
3. 添加水印和报告；
4. 质量评估和失败回退。

## 6. 风险

| 风险 | 应对 |
|---|---|
| 未授权换脸滥用 | 强制 consent manifest，默认水印，审计日志 |
| 模型效果不稳定 | 先做检测/轨迹可视化，再接换脸 |
| 低清/侧脸失败 | 输出质量评分，低置信度跳过 |
| 性能慢 | 先离线处理，后续批处理/ GPU 加速 |
| 法律风险 | 不做公众人物库、不隐藏生成痕迹 |
