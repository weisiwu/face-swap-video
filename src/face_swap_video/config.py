from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


class ConfigError(ValueError):
    """Raised when pipeline config is invalid."""


@dataclass(frozen=True)
class PipelineConfig:
    source_face: Path
    target_video: Path
    output_dir: Path
    consent_manifest: Path
    watermark_text: str = "AI-generated / authorized face swap"
    dry_run: bool = False

    @classmethod
    def from_json(cls, path: str | Path) -> "PipelineConfig":
        config_path = Path(path).expanduser().resolve()
        data = json.loads(config_path.read_text(encoding="utf-8"))
        base = config_path.parent

        required = ["source_face", "target_video", "output_dir", "consent_manifest"]
        missing = [key for key in required if not data.get(key)]
        if missing:
            raise ConfigError(f"missing required config fields: {', '.join(missing)}")

        def resolve(value: str) -> Path:
            p = Path(value).expanduser()
            return p if p.is_absolute() else (base / p).resolve()

        watermark = str(data.get("watermark_text") or "").strip()
        if not watermark:
            raise ConfigError("watermark_text is required; outputs must disclose AI-generated face swap")

        return cls(
            source_face=resolve(data["source_face"]),
            target_video=resolve(data["target_video"]),
            output_dir=resolve(data["output_dir"]),
            consent_manifest=resolve(data["consent_manifest"]),
            watermark_text=watermark,
            dry_run=bool(data.get("dry_run", False)),
        )
