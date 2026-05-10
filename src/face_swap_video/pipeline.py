from __future__ import annotations

from dataclasses import asdict

from .config import PipelineConfig
from .safety import ConsentManifest, assert_watermark_enabled


class FaceSwapPipeline:
    """MVP pipeline: safety-gated dry-run first, model integration later."""

    def __init__(self, config: PipelineConfig):
        self.config = config

    def run(self) -> dict:
        assert_watermark_enabled(self.config.watermark_text)
        manifest = ConsentManifest.load(self.config.consent_manifest)
        manifest.assert_authorized(
            source_face=self.config.source_face,
            target_video=self.config.target_video,
        )
        self.config.output_dir.mkdir(parents=True, exist_ok=True)
        return {
            "status": "dry_run_ok" if self.config.dry_run else "not_implemented",
            "message": "Safety checks passed. Model execution is not implemented in MVP skeleton.",
            "config": {k: str(v) for k, v in asdict(self.config).items()},
        }
