# face-swap-video Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 构建一个授权素材下的视频人脸检测与换脸工具，先完成安全可运行的 CLI 骨架，再逐步接入人脸检测和换脸模型。

**Architecture:** Python 包结构，CLI 调用 Pipeline。Pipeline 先经过 Safety Gate 校验授权与水印策略，再执行视频处理、检测、换脸和报告输出。MVP 阶段模型调用为 stub/dry-run，优先保证项目边界和测试体系。

**Tech Stack:** Python 3.11+、pytest、dataclass、argparse；后续接入 OpenCV、InsightFace、ffmpeg。

---

## Task 1: 完成安全清单校验

**Objective:** 实现 consent_manifest 读取与 source/target 授权校验。

**Files:**
- Modify: `src/face_swap_video/safety.py`
- Test: `tests/test_safety.py`

**Verification:**

```bash
pytest tests/test_safety.py -q
```

## Task 2: 完成配置解析

**Objective:** 实现 PipelineConfig 从 JSON 加载，并校验必填字段。

**Files:**
- Modify: `src/face_swap_video/config.py`
- Test: `tests/test_config.py`

**Verification:**

```bash
pytest tests/test_config.py -q
```

## Task 3: 完成 CLI dry-run

**Objective:** 让 `python -m face_swap_video --config xxx --dry-run` 能执行授权校验并输出结果。

**Files:**
- Modify: `src/face_swap_video/cli.py`
- Modify: `src/face_swap_video/pipeline.py`

**Verification:**

```bash
python -m face_swap_video --help
pytest -q
```

## Task 4: 接入视频抽帧与人脸检测接口

**Objective:** 添加 VideoReader 与 FaceDetector 抽象接口，先用 mock/stub 测试。

**Files:**
- Create: `src/face_swap_video/video.py`
- Create: `src/face_swap_video/detector.py`
- Create: `tests/test_detector_contract.py`

## Task 5: 接入换脸引擎适配层

**Objective:** 定义 FaceSwapEngine 接口，为后续接入 inswapper/SimSwap/FaceFusion 留出统一边界。

**Files:**
- Create: `src/face_swap_video/swapper.py`
- Create: `tests/test_swapper_contract.py`

## Task 6: 输出报告与水印

**Objective:** 生成 report.json/run_manifest.json，并确保默认水印策略不可绕过。

**Files:**
- Create: `src/face_swap_video/report.py`
- Modify: `src/face_swap_video/pipeline.py`
- Test: `tests/test_report.py`
