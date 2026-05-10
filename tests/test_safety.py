import json
from datetime import date, timedelta

import pytest

from face_swap_video.safety import ConsentManifest, SafetyError, assert_watermark_enabled


def test_watermark_required():
    with pytest.raises(SafetyError):
        assert_watermark_enabled("")


def test_authorized_source_and_target(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    source = (tmp_path / "source.jpg").resolve()
    target = (tmp_path / "target.mp4").resolve()
    manifest = tmp_path / "consent.json"
    manifest.write_text(json.dumps({
        "source_faces": [{
            "path": str(source),
            "allowed_use": ["face_swap_test"],
            "expires_at": str(date.today() + timedelta(days=10))
        }],
        "target_videos": [{
            "path": str(target),
            "allowed_use": ["face_swap_test"]
        }]
    }), encoding="utf-8")

    ConsentManifest.load(manifest).assert_authorized(source_face=source, target_video=target)


def test_relative_manifest_paths_resolve_from_manifest_dir(tmp_path):
    source = (tmp_path / "assets/source/person_a.jpg").resolve()
    target = (tmp_path / "assets/input/video.mp4").resolve()
    manifest = tmp_path / "consent.json"
    manifest.write_text(json.dumps({
        "source_faces": [{
            "path": "assets/source/person_a.jpg",
            "allowed_use": ["face_swap_test"],
            "expires_at": str(date.today() + timedelta(days=10))
        }],
        "target_videos": [{
            "path": "assets/input/video.mp4",
            "allowed_use": ["face_swap_test"]
        }]
    }), encoding="utf-8")

    ConsentManifest.load(manifest).assert_authorized(source_face=source, target_video=target)


def test_rejects_unauthorized_source(tmp_path):
    source = (tmp_path / "source.jpg").resolve()
    target = (tmp_path / "target.mp4").resolve()
    manifest = tmp_path / "consent.json"
    manifest.write_text(json.dumps({
        "source_faces": [],
        "target_videos": [{"path": str(target), "allowed_use": ["face_swap_test"]}]
    }), encoding="utf-8")

    with pytest.raises(SafetyError):
        ConsentManifest.load(manifest).assert_authorized(source_face=source, target_video=target)
