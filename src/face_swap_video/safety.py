from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any


class SafetyError(PermissionError):
    """Raised when consent or disclosure requirements are not satisfied."""


@dataclass(frozen=True)
class ConsentManifest:
    raw: dict[str, Any]
    path: Path

    @classmethod
    def load(cls, path: str | Path) -> "ConsentManifest":
        manifest_path = Path(path).expanduser().resolve()
        if not manifest_path.exists():
            raise SafetyError(f"consent manifest not found: {manifest_path}")
        return cls(json.loads(manifest_path.read_text(encoding="utf-8")), manifest_path)

    def assert_authorized(self, *, source_face: Path, target_video: Path, purpose: str = "face_swap_test") -> None:
        source_ok = _is_authorized_item(
            self.raw.get("source_faces", []),
            source_face,
            base_dir=self.path.parent,
            purpose=purpose,
            check_expiry=True,
        )
        if not source_ok:
            raise SafetyError(f"source face is not authorized for purpose={purpose}: {source_face}")

        target_ok = _is_authorized_item(
            self.raw.get("target_videos", []),
            target_video,
            base_dir=self.path.parent,
            purpose=purpose,
            check_expiry=False,
        )
        if not target_ok:
            raise SafetyError(f"target video is not authorized for purpose={purpose}: {target_video}")


def assert_watermark_enabled(watermark_text: str) -> None:
    if not (watermark_text or "").strip():
        raise SafetyError("watermark_text is required; do not hide AI-generated face swap disclosure")


def _is_authorized_item(
    items: list[dict[str, Any]],
    path: Path,
    *,
    base_dir: Path,
    purpose: str,
    check_expiry: bool,
) -> bool:
    target = str(path.expanduser().resolve())
    for item in items:
        item_path = Path(str(item.get("path", ""))).expanduser()
        if not item_path.is_absolute():
            item_path = (base_dir / item_path).resolve()
        if str(item_path) != target:
            continue
        allowed = item.get("allowed_use", [])
        if purpose not in allowed:
            return False
        if check_expiry and item.get("expires_at"):
            if date.fromisoformat(str(item["expires_at"])) < date.today():
                return False
        return True
    return False
