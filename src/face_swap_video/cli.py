from __future__ import annotations

import argparse
import json
import sys

from .config import ConfigError, PipelineConfig
from .pipeline import FaceSwapPipeline
from .safety import SafetyError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="face-swap-video",
        description="Authorized video face detection and face swap pipeline.",
    )
    parser.add_argument("--config", required=False, help="Path to pipeline_config.json")
    parser.add_argument("--dry-run", action="store_true", help="Validate config/consent without model execution")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.config:
        parser.print_help()
        return 0

    try:
        config = PipelineConfig.from_json(args.config)
        if args.dry_run:
            config = PipelineConfig(
                source_face=config.source_face,
                target_video=config.target_video,
                output_dir=config.output_dir,
                consent_manifest=config.consent_manifest,
                watermark_text=config.watermark_text,
                dry_run=True,
            )
        result = FaceSwapPipeline(config).run()
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["status"] == "dry_run_ok" else 2
    except (ConfigError, SafetyError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
