import asyncio
import importlib.util
import sys
import uuid
from pathlib import Path


SERVER_PATH = Path(__file__).with_name("server.py")


def load_server_module(monkeypatch, **env):
    for key in [
        "VIDEO_MAX_WORKERS",
        "FF_VIDEO_PROFILE",
        "FF_TARGET_MAX_WIDTH",
        "FF_TARGET_FPS",
        "FF_PREPROCESS_TIMEOUT_SECONDS",
        "FF_OUTPUT_VIDEO_FPS",
        "FF_OUTPUT_VIDEO_QUALITY",
        "FF_FACE_SWAPPER_MODEL",
        "API_PORT",
        "FC_SERVER_PORT",
        "PORT",
        "FF_PYTHON",
    ]:
        monkeypatch.delenv(key, raising=False)
    for key, value in env.items():
        monkeypatch.setenv(key, str(value))

    module_name = f"api_server_under_test_{uuid.uuid4().hex}"
    spec = importlib.util.spec_from_file_location(module_name, SERVER_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
        return module
    except Exception:
        sys.modules.pop(module_name, None)
        raise


def shutdown_module_executor(module):
    module.VIDEO_JOB_EXECUTOR.shutdown(wait=False, cancel_futures=True)


def test_default_video_profile_is_preview_and_single_worker(monkeypatch):
    module = load_server_module(monkeypatch)
    try:
        assert module.VIDEO_MAX_WORKERS == 1
        assert module.FF_VIDEO_PROFILE == "preview"
        assert module.FF_TARGET_MAX_WIDTH == 360
        assert module.FF_TARGET_FPS == 12
        assert module.FF_OUTPUT_VIDEO_FPS == "12"
        assert module.FF_OUTPUT_VIDEO_QUALITY == "50"
        assert module.FF_FACE_SWAPPER_MODEL == "inswapper_128"
        assert module.FF_PREPROCESS_TIMEOUT_SECONDS == 120
    finally:
        shutdown_module_executor(module)


def test_video_profile_fast_keeps_540p_18fps_defaults(monkeypatch):
    module = load_server_module(monkeypatch, FF_VIDEO_PROFILE="fast")
    try:
        assert module.FF_VIDEO_PROFILE == "fast"
        assert module.FF_TARGET_MAX_WIDTH == 540
        assert module.FF_TARGET_FPS == 18
        assert module.FF_OUTPUT_VIDEO_FPS == "18"
        assert module.FF_OUTPUT_VIDEO_QUALITY == "60"
    finally:
        shutdown_module_executor(module)


def test_video_profile_low_alias_maps_to_preview(monkeypatch):
    module = load_server_module(monkeypatch, FF_VIDEO_PROFILE="low")
    try:
        assert module.FF_VIDEO_PROFILE == "preview"
        assert module.FF_TARGET_MAX_WIDTH == 360
        assert module.FF_TARGET_FPS == 12
        assert module.FF_OUTPUT_VIDEO_QUALITY == "50"
    finally:
        shutdown_module_executor(module)


def test_video_profile_high_quality_keeps_720p_24fps_defaults(monkeypatch):
    module = load_server_module(monkeypatch, FF_VIDEO_PROFILE="high_quality", VIDEO_MAX_WORKERS="2")
    try:
        assert module.VIDEO_MAX_WORKERS == 2
        assert module.FF_VIDEO_PROFILE == "high_quality"
        assert module.FF_TARGET_MAX_WIDTH == 720
        assert module.FF_TARGET_FPS == 24
        assert module.FF_OUTPUT_VIDEO_FPS == "24"
        assert module.FF_OUTPUT_VIDEO_QUALITY == "70"
    finally:
        shutdown_module_executor(module)


def test_explicit_video_env_overrides_profile_defaults(monkeypatch):
    module = load_server_module(
        monkeypatch,
        FF_VIDEO_PROFILE="fast",
        FF_TARGET_MAX_WIDTH="480",
        FF_TARGET_FPS="15",
        FF_OUTPUT_VIDEO_FPS="15",
        FF_OUTPUT_VIDEO_QUALITY="55",
        FF_PREPROCESS_TIMEOUT_SECONDS="45",
    )
    try:
        assert module.FF_TARGET_MAX_WIDTH == 480
        assert module.FF_TARGET_FPS == 15
        assert module.FF_OUTPUT_VIDEO_FPS == "15"
        assert module.FF_OUTPUT_VIDEO_QUALITY == "55"
        assert module.FF_PREPROCESS_TIMEOUT_SECONDS == 45
    finally:
        shutdown_module_executor(module)


def test_video_filter_aligns_dimensions_for_android_mediacodec(monkeypatch):
    module = load_server_module(monkeypatch)
    try:
        video_filter = module._codec_safe_video_filter()
        assert "trunc(iw/16)*16" in video_filter
        assert "trunc(ih/16)*16" in video_filter
        assert "fps=12" in video_filter
    finally:
        shutdown_module_executor(module)


def test_swap_status_returns_stage_and_progress(monkeypatch):
    module = load_server_module(monkeypatch)
    try:
        job_id = "job-status-test"
        module._set_job(job_id, status="processing")
        module._update_job_stage(job_id, "swapping_frame", 0.42)

        payload = asyncio.run(module.swap_status(job_id))

        assert payload["status"] == "processing"
        assert payload["stage"] == "swapping_frame"
        assert payload["stage_label"] == "逐帧换脸"
        assert payload["progress"] == 0.42
        assert payload["video_profile"] == "preview"

        health_payload = asyncio.run(module.health())
        assert health_payload["face_swapper_model"] == "inswapper_128"
        assert health_payload["preprocess_timeout_seconds"] == 120
    finally:
        shutdown_module_executor(module)
