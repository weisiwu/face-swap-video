# face-swap-video

> 授权素材下的视频人脸检测与换脸工具：输入源人脸与目标视频，检测目标视频中的人脸轨迹，在合规授权前提下生成带水印/元数据标记的换脸视频。

## 项目边界

本项目只面向以下场景：

- 用户拥有或已获得明确授权的人脸素材；
- 内部创意、影视预演、虚拟形象、数字人内容生产；
- 明确标注 AI 生成或换脸水印；
- 保留处理日志、授权记录与输出元数据。

本项目不支持：

- 未授权替换真实人物人脸；
- 冒充公众人物、诈骗、色情、诽谤、身份欺骗等用途；
- 去水印、规避检测、隐藏 AI 生成痕迹。

## 初始目录

```text
face-swap-video/
├── docs/
│   ├── PRD.md
│   ├── TECH_DESIGN.md
│   ├── TEST_CASES.md
│   └── IMPLEMENTATION_PLAN.md
├── context/
│   └── project-context.md
├── src/face_swap_video/
│   ├── __init__.py
│   ├── __main__.py
│   ├── cli.py
│   ├── config.py
│   ├── safety.py
│   └── pipeline.py
├── tests/
│   ├── test_safety.py
│   └── test_config.py
├── pyproject.toml
└── README.md
```

## 快速开始

```bash
cd apps/face-swap-video
python3 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
pytest -q
python -m face_swap_video --help
```

## 当前状态

MVP 规划与项目骨架已建立；尚未接入实际人脸检测/换脸模型。
