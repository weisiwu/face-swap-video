import json

import pytest

from face_swap_video.config import ConfigError, PipelineConfig


def test_config_requires_watermark(tmp_path):
    cfg = tmp_path / "pipeline_config.json"
    cfg.write_text(json.dumps({
        "source_face": "source.jpg",
        "target_video": "target.mp4",
        "output_dir": "out",
        "consent_manifest": "consent.json",
        "watermark_text": ""
    }), encoding="utf-8")

    with pytest.raises(ConfigError):
        PipelineConfig.from_json(cfg)


def test_config_resolves_relative_paths(tmp_path):
    cfg = tmp_path / "pipeline_config.json"
    cfg.write_text(json.dumps({
        "source_face": "source.jpg",
        "target_video": "target.mp4",
        "output_dir": "out",
        "consent_manifest": "consent.json",
        "watermark_text": "AI-generated"
    }), encoding="utf-8")

    parsed = PipelineConfig.from_json(cfg)
    assert parsed.source_face == (tmp_path / "source.jpg").resolve()
    assert parsed.output_dir == (tmp_path / "out").resolve()
