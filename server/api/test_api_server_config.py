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
        "FF_EXECUTION_THREAD_COUNT",
        "FF_VIDEO_ENGINE",
        "FF_VIDEO_JOB_MODE",
        "API_PORT",
        "FC_SERVER_PORT",
        "PORT",
        "FF_PYTHON",
        "OSS_JOB_STORE_ENABLED",
        "LOCAL_JOB_STORE_DIR",
        "OSS_JOB_PREFIX",
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
        assert module.FF_EXECUTION_THREAD_COUNT == "1"
        assert module.FF_VIDEO_ENGINE == "facefusion"
        assert module.FF_VIDEO_JOB_MODE == "background"
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


def test_preprocess_falls_back_when_optimized_video_has_no_readable_resolution(monkeypatch, tmp_path):
    module = load_server_module(monkeypatch)
    try:
        target_path = tmp_path / "target.mp4"
        target_path.write_bytes(b"original-video")
        optimized_path = target_path.with_name("target_optimized.mp4")

        class FakeCompletedProcess:
            returncode = 0
            stdout = ""
            stderr = ""

        def fake_run(cmd, capture_output=True, text=True, timeout=60):
            optimized_path.write_bytes(b"tiny-invalid-video")
            return FakeCompletedProcess()

        monkeypatch.setattr(module.shutil, "which", lambda name: "/usr/bin/ffmpeg" if name == "ffmpeg" else None)
        monkeypatch.setattr(module.subprocess, "run", fake_run)
        monkeypatch.setattr(module, "_video_has_readable_resolution", lambda path: path == target_path)

        result = module._preprocess_target_video(target_path)

        assert result == target_path
        assert not optimized_path.exists()
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
        assert health_payload["execution_thread_count"] == "1"
        assert health_payload["video_engine"] == "facefusion"
        assert health_payload["video_job_mode"] == "background"
    finally:
        shutdown_module_executor(module)


def test_job_status_persists_to_job_store_and_recovers_after_memory_loss(monkeypatch, tmp_path):
    module = load_server_module(
        monkeypatch,
        OSS_JOB_STORE_ENABLED="local",
        LOCAL_JOB_STORE_DIR=str(tmp_path),
        OSS_JOB_PREFIX="face-swap-video/jobs",
    )
    try:
        job_id = "job-persist-test"
        module._set_job(job_id, status="processing", stage="queued", progress=0.0)
        module._update_job_stage(job_id, "swapping_frame", 0.55)

        module.JOBS.clear()
        payload = asyncio.run(module.swap_status(job_id))

        assert payload["job_id"] == job_id
        assert payload["status"] == "processing"
        assert payload["stage"] == "swapping_frame"
        assert payload["progress"] == 0.55
        assert payload["job_store"] == "local"
        assert payload["status_persisted"] is True
    finally:
        shutdown_module_executor(module)


def test_swap_result_can_be_restored_from_job_store_when_local_file_is_missing(monkeypatch, tmp_path):
    module = load_server_module(
        monkeypatch,
        OSS_JOB_STORE_ENABLED="local",
        LOCAL_JOB_STORE_DIR=str(tmp_path),
        OSS_JOB_PREFIX="face-swap-video/jobs",
    )
    try:
        job_id = "job-result-store-test"
        missing_output = tmp_path / "missing-result.mp4"
        module.JOB_STORE.save_bytes(job_id, "output/result.mp4", b"persisted-mp4")
        module._set_job(
            job_id,
            status="completed",
            output_path=str(missing_output),
            output_key="face-swap-video/jobs/job-result-store-test/output/result.mp4",
        )
        module.JOBS.clear()

        response = asyncio.run(module.swap_result(job_id))

        assert response.media_type == "video/mp4"
        assert response.body == b"persisted-mp4"
    finally:
        shutdown_module_executor(module)


def test_static_first_frame_engine_swaps_extracted_frame_instead_of_passthrough(monkeypatch, tmp_path):
    module = load_server_module(monkeypatch, FF_VIDEO_ENGINE="static_first_frame")
    try:
        job_id = "job-static-frame-test"
        source_path = tmp_path / "source.jpg"
        target_path = tmp_path / "target.mp4"
        output_path = tmp_path / "result.mp4"
        source_path.write_bytes(b"source-face")
        target_path.write_bytes(b"original-target-video")
        facefusion_calls = []

        def fake_read_first_frame(video_path, frame_path):
            assert video_path == target_path
            frame_path.write_bytes(b"target-first-frame")
            return 1.0, 12.0

        def fake_run_facefusion(args, timeout=600, job_id=None, output_path=None):
            facefusion_calls.append(args)
            swapped_frame = Path(args[args.index("--output-path") + 1])
            swapped_frame.write_bytes(b"swapped-frame")
            return 0, "", ""

        def fake_encode_static_frame_video(frame_path, encoded_output_path, duration):
            assert frame_path.read_bytes() == b"swapped-frame"
            encoded_output_path.write_bytes(b"encoded-swapped-video")

        monkeypatch.setattr(module, "_read_first_frame_with_cv2", fake_read_first_frame)
        monkeypatch.setattr(module, "_run_facefusion", fake_run_facefusion)
        monkeypatch.setattr(module, "_encode_static_frame_video_with_cv2", fake_encode_static_frame_video)
        monkeypatch.setattr(module, "_copy_audio_from_target", lambda target, swapped: swapped)

        result_path = module._run_static_first_frame_video_swap(job_id, source_path, target_path, output_path)

        assert result_path == output_path
        assert output_path.read_bytes() == b"encoded-swapped-video"
        assert output_path.read_bytes() != target_path.read_bytes()
        assert len(facefusion_calls) == 1
        facefusion_args = facefusion_calls[0]
        assert facefusion_args[facefusion_args.index("--source-paths") + 1] == str(source_path)
        assert facefusion_args[facefusion_args.index("--processors") + 1] == module.FF_PROCESSORS
        assert facefusion_args[facefusion_args.index("--face-swapper-model") + 1] == module.FF_FACE_SWAPPER_MODEL
    finally:
        shutdown_module_executor(module)


def test_static_first_frame_encoder_uses_h264_for_android_preview(monkeypatch, tmp_path):
    module = load_server_module(monkeypatch, FF_VIDEO_ENGINE="static_first_frame", FF_OUTPUT_VIDEO_FPS="12")
    try:
        frame_path = tmp_path / "swapped.jpg"
        output_path = tmp_path / "result.mp4"
        frame_path.write_bytes(b"jpeg-frame")
        captured = {}

        class FakeCompletedProcess:
            returncode = 0
            stdout = ""
            stderr = ""

        def fake_run(cmd, capture_output=True, text=True, timeout=60):
            captured["cmd"] = cmd
            captured["timeout"] = timeout
            output_path.write_bytes(b"h264-video")
            return FakeCompletedProcess()

        monkeypatch.setattr(module.shutil, "which", lambda name: "/usr/bin/ffmpeg" if name == "ffmpeg" else None)
        monkeypatch.setattr(module.subprocess, "run", fake_run)

        module._encode_static_frame_video_with_cv2(frame_path, output_path, 5.0)

        cmd = captured["cmd"]
        assert "ffmpeg" == cmd[0]
        assert cmd[cmd.index("-c:v") + 1] == "libx264"
        assert cmd[cmd.index("-pix_fmt") + 1] == "yuv420p"
        assert "format=yuv420p" in cmd[cmd.index("-vf") + 1]
        assert output_path.read_bytes() == b"h264-video"
    finally:
        shutdown_module_executor(module)


def test_static_first_frame_engine_falls_back_to_source_frame_when_video_decode_fails(monkeypatch, tmp_path):
    module = load_server_module(monkeypatch, FF_VIDEO_ENGINE="static_first_frame")
    try:
        job_id = "job-static-frame-fallback-test"
        source_path = tmp_path / "source.jpg"
        target_path = tmp_path / "target.mp4"
        output_path = tmp_path / "result.mp4"
        source_path.write_bytes(b"source-face-image")
        target_path.write_bytes(b"original-target-video")
        target_frame_payloads = []

        def fake_read_first_frame(video_path, frame_path):
            raise RuntimeError("decode hung")

        def fake_run_facefusion(args, timeout=600, job_id=None, output_path=None):
            target_frame = Path(args[args.index("--target-path") + 1])
            target_frame_payloads.append(target_frame.read_bytes())
            swapped_frame = Path(args[args.index("--output-path") + 1])
            swapped_frame.write_bytes(b"swapped-source-frame")
            return 0, "", ""

        def fake_encode_static_frame_video(frame_path, encoded_output_path, duration):
            assert frame_path.read_bytes() == b"swapped-source-frame"
            assert duration == 5.0
            encoded_output_path.write_bytes(b"encoded-fallback-video")

        monkeypatch.setattr(module, "_read_first_frame_with_cv2", fake_read_first_frame)
        monkeypatch.setattr(module, "_video_duration_seconds", lambda video_path: 5.0)
        monkeypatch.setattr(module, "_run_facefusion", fake_run_facefusion)
        monkeypatch.setattr(module, "_encode_static_frame_video_with_cv2", fake_encode_static_frame_video)
        monkeypatch.setattr(module, "_copy_audio_from_target", lambda target, swapped: swapped)

        result_path = module._run_static_first_frame_video_swap(job_id, source_path, target_path, output_path)

        assert result_path == output_path
        assert output_path.read_bytes() == b"encoded-fallback-video"
        assert output_path.read_bytes() != target_path.read_bytes()
        assert target_frame_payloads == [b"source-face-image"]
    finally:
        shutdown_module_executor(module)
