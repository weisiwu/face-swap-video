#!/usr/bin/env python3
"""FaceFusion REST API server — provides clean endpoints for the Android app."""

import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import cv2

from job_store import create_job_store_from_env

# ── Config ──────────────────────────────────────────────────────────────
API_PORT = int(os.environ.get("API_PORT", os.environ.get("FC_SERVER_PORT", os.environ.get("PORT", "9999"))))
FF_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # server/
FF_PYTHON = os.environ.get("FF_PYTHON", "/opt/miniconda3/envs/facefusion/bin/python")
FF_EXECUTION_PROVIDERS = os.environ.get("FF_EXECUTION_PROVIDERS", "coreml")
FF_PROCESSORS = os.environ.get("FF_PROCESSORS", "face_swapper")
# Use the model that is packaged into the FC image by default. The fp16 variant
# is not available in the local .assets cache, so defaulting to it forces
# FaceFusion to download at runtime and can hang in FC when model hosts are
# unreachable.
FF_FACE_SWAPPER_MODEL = os.environ.get("FF_FACE_SWAPPER_MODEL", "inswapper_128")
FF_EXECUTION_THREAD_COUNT = os.environ.get("FF_EXECUTION_THREAD_COUNT", "1")
FF_FACE_DETECTOR_MODEL = os.environ.get("FF_FACE_DETECTOR_MODEL", "yolo_face")
FF_FACE_LANDMARKER_MODEL = os.environ.get("FF_FACE_LANDMARKER_MODEL", "2dfan4")
FF_TEMP_PATH = os.environ.get("FF_TEMP_PATH", os.path.join(tempfile.gettempdir(), "facefusion-temp"))
FF_VIDEO_MEMORY_STRATEGY = os.environ.get("FF_VIDEO_MEMORY_STRATEGY", "strict")
FF_VIDEO_PROFILE = os.environ.get("FF_VIDEO_PROFILE", "preview").strip().lower()
if FF_VIDEO_PROFILE in {"low", "mvp"}:
    FF_VIDEO_PROFILE = "preview"
if FF_VIDEO_PROFILE in {"high", "quality", "hq"}:
    FF_VIDEO_PROFILE = "high_quality"
if FF_VIDEO_PROFILE not in {"preview", "fast", "high_quality"}:
    FF_VIDEO_PROFILE = "preview"
_PROFILE_DEFAULTS = {
    "preview": {
        "target_max_width": "360",
        "target_fps": "12",
        "output_video_fps": "12",
        "output_video_quality": "50",
    },
    "fast": {
        "target_max_width": "540",
        "target_fps": "18",
        "output_video_fps": "18",
        "output_video_quality": "60",
    },
    "high_quality": {
        "target_max_width": "720",
        "target_fps": "24",
        "output_video_fps": "24",
        "output_video_quality": "70",
    },
}
_PROFILE = _PROFILE_DEFAULTS[FF_VIDEO_PROFILE]
FF_OUTPUT_VIDEO_PRESET = os.environ.get("FF_OUTPUT_VIDEO_PRESET", "ultrafast")
FF_OUTPUT_VIDEO_QUALITY = os.environ.get("FF_OUTPUT_VIDEO_QUALITY", _PROFILE["output_video_quality"])
FF_OUTPUT_VIDEO_FPS = os.environ.get("FF_OUTPUT_VIDEO_FPS", _PROFILE["output_video_fps"])
FF_OPTIMIZE_TARGET_VIDEO = os.environ.get("FF_OPTIMIZE_TARGET_VIDEO", "1") != "0"
FF_TARGET_MAX_WIDTH = int(os.environ.get("FF_TARGET_MAX_WIDTH", _PROFILE["target_max_width"]))
FF_TARGET_FPS = int(os.environ.get("FF_TARGET_FPS", _PROFILE["target_fps"]))
FF_PREPROCESS_TIMEOUT_SECONDS = max(5, int(os.environ.get("FF_PREPROCESS_TIMEOUT_SECONDS", "120")))
FF_FACEFUSION_TIMEOUT_SECONDS = max(60, int(os.environ.get("FF_FACEFUSION_TIMEOUT_SECONDS", "900")))
FF_STATIC_FRAME_DECODE_TIMEOUT_SECONDS = max(3, int(os.environ.get("FF_STATIC_FRAME_DECODE_TIMEOUT_SECONDS", "20")))
FF_LOG_LEVEL = os.environ.get("FF_LOG_LEVEL", "info")
FF_VIDEO_ENGINE = os.environ.get("FF_VIDEO_ENGINE", "facefusion").strip().lower()
if FF_VIDEO_ENGINE not in {"facefusion", "static_first_frame", "frame_by_frame"}:
    FF_VIDEO_ENGINE = "facefusion"
FF_VIDEO_JOB_MODE = os.environ.get("FF_VIDEO_JOB_MODE", "background").strip().lower()
if FF_VIDEO_JOB_MODE not in {"background", "inline"}:
    FF_VIDEO_JOB_MODE = "background"
VIDEO_MAX_WORKERS = max(1, min(int(os.environ.get("VIDEO_MAX_WORKERS", "1")), 4))
FFMPEG_SEARCH_PATHS = [
    os.path.expanduser("~/miniconda3/bin"),
    "/opt/miniconda3/bin",
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
]
os.environ["PATH"] = os.pathsep.join(
    [p for p in FFMPEG_SEARCH_PATHS if os.path.isdir(p)] + [os.environ.get("PATH", "")]
)
OUTPUT_BASE = Path(os.environ.get("FF_OUTPUT_DIR", os.path.join(FF_DIR, ".api_output")))
OUTPUT_BASE.mkdir(parents=True, exist_ok=True)
Path(FF_TEMP_PATH).mkdir(parents=True, exist_ok=True)
JOBS: dict[str, dict] = {}
JOB_PROCESSES: dict[str, subprocess.Popen] = {}
JOBS_LOCK = threading.Lock()
JOB_STORE = create_job_store_from_env()
VIDEO_JOB_EXECUTOR = ThreadPoolExecutor(max_workers=VIDEO_MAX_WORKERS, thread_name_prefix="facefusion-video")

# ── App ─────────────────────────────────────────────────────────────────
try:
    from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import FileResponse, JSONResponse, Response
    import uvicorn
except ImportError:
    print("Installing dependencies...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "fastapi", "uvicorn", "python-multipart", "-q"])
    from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import FileResponse, JSONResponse, Response
    import uvicorn

app = FastAPI(title="FaceSwap API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def _log_upload_receive_timing(request: Request, call_next):
    """Measure raw ASGI request-body receive timing before FastAPI parses multipart.

    Endpoint code starts only after multipart parsing, so this middleware is the
    boundary that tells us whether time was spent on phone/network/tunnel ingress
    versus server-side saving/queueing.
    """
    if request.url.path not in {"/api/swap/video/job", "/api/swap/video", "/api/swap/image"}:
        return await call_next(request)

    request_id = uuid.uuid4().hex[:8]
    content_length = request.headers.get("content-length", "unknown")
    content_type = request.headers.get("content-type", "unknown")
    started_at = time.perf_counter()
    first_byte_at: float | None = None
    last_body_at: float | None = None
    received_bytes = 0
    chunk_count = 0
    max_chunk_gap = 0.0
    previous_chunk_at = started_at
    original_receive = request._receive

    _upload_log(
        f"[upload:{request_id}] receive_start path={request.url.path} "
        f"content_length={content_length} content_type={content_type}"
    )

    async def receive_with_metrics():
        nonlocal first_byte_at, last_body_at, received_bytes, chunk_count, max_chunk_gap, previous_chunk_at
        message = await original_receive()
        if message.get("type") == "http.request":
            now = time.perf_counter()
            body = message.get("body") or b""
            if body:
                if first_byte_at is None:
                    first_byte_at = now
                gap = now - previous_chunk_at
                if gap > max_chunk_gap:
                    max_chunk_gap = gap
                previous_chunk_at = now
                received_bytes += len(body)
                chunk_count += 1
                last_body_at = now
            if not message.get("more_body", False):
                elapsed = now - started_at
                active_receive = (last_body_at or now) - (first_byte_at or started_at)
                mbps = _throughput_mbps(received_bytes, active_receive)
                _upload_log(
                    f"[upload:{request_id}] receive_complete path={request.url.path} "
                    f"received_bytes={received_bytes} chunk_count={chunk_count} "
                    f"elapsed_seconds={elapsed:.3f} active_receive_seconds={active_receive:.3f} "
                    f"throughput_mbps={mbps:.2f} first_byte_seconds={(first_byte_at - started_at) if first_byte_at else -1:.3f} "
                    f"max_chunk_gap_seconds={max_chunk_gap:.3f}"
                )
        return message

    request._receive = receive_with_metrics
    request.state.upload_request_id = request_id
    response = await call_next(request)
    total_elapsed = time.perf_counter() - started_at
    _upload_log(
        f"[upload:{request_id}] response_start path={request.url.path} "
        f"status_code={response.status_code} total_elapsed_seconds={total_elapsed:.3f} "
        f"received_bytes={received_bytes}"
    )
    response.headers["X-Upload-Debug-Id"] = request_id
    return response

# ── Helpers ──────────────────────────────────────────────────────────────

def _upload_log(message: str) -> None:
    print(message, flush=True)


def _throughput_mbps(bytes_count: int, seconds: float) -> float:
    if seconds <= 0:
        return 0.0
    return bytes_count * 8 / seconds / 1_000_000


def _tail_file(path: str | Path | None, max_chars: int = 4000) -> str:
    if not path:
        return ""
    p = Path(path)
    try:
        if not p.exists():
            return ""
        with p.open("rb") as f:
            try:
                f.seek(-max_chars, os.SEEK_END)
            except OSError:
                f.seek(0)
            return f.read(max_chars).decode("utf-8", "replace")
    except Exception as exc:
        return f"<tail failed: {exc}>"


def _run_facefusion(
    args: list[str],
    timeout: int = 600,
    job_id: str | None = None,
    output_path: Path | None = None,
) -> tuple[int, str, str]:
    """Run FaceFusion headless-run and return (exit_code, stdout_tail, stderr_tail)."""
    # Run FaceFusion via its script file instead of a `python -c runpy` wrapper.
    # The wrapper broke some FaceFusion child-process/import behavior in FC and
    # caused even image swaps to exit without producing output. Keep the command
    # boring and rely on stdout/stderr files plus status heartbeat for debugging.
    cmd = [FF_PYTHON, "facefusion.py", "headless-run"] + args
    log_token = job_id or uuid.uuid4().hex[:8]
    stdout_path = Path(tempfile.gettempdir()) / f"facefusion_{log_token}_stdout.log"
    stderr_path = Path(tempfile.gettempdir()) / f"facefusion_{log_token}_stderr.log"
    stdout_file = stdout_path.open("w", encoding="utf-8", errors="replace")
    stderr_file = stderr_path.open("w", encoding="utf-8", errors="replace")
    process = subprocess.Popen(cmd, cwd=FF_DIR, stdout=stdout_file, stderr=stderr_file, text=True, start_new_session=True)
    if job_id:
        _set_job(
            job_id,
            facefusion_pid=process.pid,
            facefusion_started_at=time.time(),
            facefusion_timeout_seconds=timeout,
            facefusion_stdout_path=str(stdout_path),
            facefusion_stderr_path=str(stderr_path),
            facefusion_cmd=" ".join(cmd),
        )
        with JOBS_LOCK:
            JOB_PROCESSES[job_id] = process
    stop_stage_tracker: threading.Event | None = None
    stage_thread: threading.Thread | None = None
    if job_id:
        stop_stage_tracker = threading.Event()
        stage_thread = threading.Thread(
            target=_track_facefusion_stage,
            args=(job_id, stop_stage_tracker, output_path),
            daemon=True,
        )
        stage_thread.start()
    try:
        return_code = process.wait(timeout=timeout)
        stdout_file.flush()
        stderr_file.flush()
        return return_code, _tail_file(stdout_path), _tail_file(stderr_path)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGUSR1)
            time.sleep(2)
        except Exception:
            pass
        _terminate_process(process)
        stdout_file.flush()
        stderr_file.flush()
        stdout_tail = _tail_file(stdout_path)
        stderr_tail = _tail_file(stderr_path)
        timeout_message = f"FaceFusion timed out after {timeout}s"
        if stderr_tail:
            timeout_message += f"; stderr_tail={stderr_tail}"
        if stdout_tail:
            timeout_message += f"; stdout_tail={stdout_tail}"
        return 124, stdout_tail, timeout_message
    finally:
        try:
            stdout_file.close()
            stderr_file.close()
        except Exception:
            pass
        if stop_stage_tracker is not None:
            stop_stage_tracker.set()
        if stage_thread is not None:
            stage_thread.join(timeout=1)
        if job_id:
            with JOBS_LOCK:
                if JOB_PROCESSES.get(job_id) is process:
                    JOB_PROCESSES.pop(job_id, None)


def _terminate_process(process: subprocess.Popen) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=10)
    except Exception:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except Exception:
            try:
                process.kill()
            except Exception:
                pass


def _save_upload(upload: UploadFile, prefix: str) -> tuple[Path, int, float]:
    """Save an uploaded file to a temp location in chunks, return path/bytes/seconds."""
    suffix = Path(upload.filename or "file").suffix or ".bin"
    out = Path(tempfile.gettempdir()) / f"{prefix}_{uuid.uuid4().hex[:8]}{suffix}"
    started_at = time.perf_counter()
    total_bytes = 0
    with open(out, "wb") as f:
        while True:
            chunk = upload.file.read(1024 * 1024)
            if not chunk:
                break
            total_bytes += len(chunk)
            f.write(chunk)
    return out, total_bytes, time.perf_counter() - started_at


def _make_output_path(prefix: str, ext: str) -> Path:
    """Generate a unique output path."""
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    uid = uuid.uuid4().hex[:8]
    return OUTPUT_BASE / f"{prefix}_{ts}_{uid}{ext}"


def _video_has_readable_resolution(video_path: Path) -> bool:
    """Return True when ffprobe can read positive video width/height.

    FaceFusion assumes `detect_video_resolution()` is not None. Very short or
    malformed ffmpeg preprocessing output can be non-empty but unreadable, which
    crashes FaceFusion before frame extraction. Treat those files as invalid and
    fall back to the original target video.
    """
    if not video_path.exists() or video_path.stat().st_size <= 0 or not shutil.which("ffprobe"):
        return False
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "json",
        str(video_path),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except Exception:
        return False
    if result.returncode != 0:
        return False
    try:
        payload = json.loads(result.stdout or "{}")
        stream = (payload.get("streams") or [{}])[0]
        return int(stream.get("width") or 0) > 0 and int(stream.get("height") or 0) > 0
    except Exception:
        return False


def _set_job(job_id: str, **values) -> None:
    with JOBS_LOCK:
        current = JOBS.setdefault(job_id, {})
        current.update(values)
        snapshot = dict(current)
    if getattr(JOB_STORE, "enabled", False):
        try:
            JOB_STORE.save_status(job_id, snapshot)
        except Exception as exc:
            print(f"[video-job:{job_id}] job_store_status_save_failed error={exc}", flush=True)


def _get_job(job_id: str) -> dict | None:
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if job:
            return dict(job)
    if getattr(JOB_STORE, "enabled", False):
        try:
            persisted = JOB_STORE.load_status(job_id)
        except Exception as exc:
            print(f"[video-job:{job_id}] job_store_status_load_failed error={exc}", flush=True)
            persisted = None
        if persisted:
            with JOBS_LOCK:
                JOBS[job_id] = dict(persisted)
            return dict(persisted)
    return None


def _persist_job_file(job_id: str, relative_key: str, path: Path) -> str | None:
    if not getattr(JOB_STORE, "enabled", False):
        return None
    try:
        return JOB_STORE.save_file(job_id, relative_key, path)
    except Exception as exc:
        print(f"[video-job:{job_id}] job_store_file_save_failed key={relative_key} error={exc}", flush=True)
        return None


def _read_job_store_bytes(job_id: str, relative_key: str) -> bytes | None:
    if not getattr(JOB_STORE, "enabled", False):
        return None
    try:
        return JOB_STORE.read_bytes(job_id, relative_key)
    except Exception as exc:
        print(f"[video-job:{job_id}] job_store_file_read_failed key={relative_key} error={exc}", flush=True)
        return None


_STAGE_LABELS = {
    "queued": "排队中",
    "preprocessing": "预处理视频",
    "detecting_face": "检测人脸",
    "swapping_frame": "逐帧换脸",
    "encoding": "编码输出",
    "completed": "处理完成",
    "failed": "处理失败",
    "cancelled": "已取消",
}


def _update_job_stage(job_id: str, stage: str, progress: float | None = None) -> None:
    values = {
        "stage": stage,
        "stage_label": _STAGE_LABELS.get(stage, stage),
        "updated_at": time.time(),
    }
    if progress is not None:
        values["progress"] = max(0.0, min(float(progress), 1.0))
    _set_job(job_id, **values)


def _track_facefusion_stage(job_id: str, stop_event: threading.Event, output_path: Path | None = None) -> None:
    started_at = time.perf_counter()
    last_log_bucket = -1
    while not stop_event.wait(3):
        job = _get_job(job_id)
        if job.get("status") == "cancelled":
            return
        elapsed = time.perf_counter() - started_at
        output_bytes = output_path.stat().st_size if output_path and output_path.exists() else 0
        _set_job(
            job_id,
            facefusion_elapsed_seconds=round(elapsed, 3),
            facefusion_output_bytes=output_bytes,
            facefusion_stdout_tail=_tail_file(job.get("facefusion_stdout_path"), 1200),
            facefusion_stderr_tail=_tail_file(job.get("facefusion_stderr_path"), 1200),
            facefusion_heartbeat_at=time.time(),
        )
        log_bucket = int(elapsed // 30)
        if log_bucket != last_log_bucket:
            last_log_bucket = log_bucket
            print(
                f"[video-job:{job_id}] facefusion_heartbeat elapsed_seconds={elapsed:.1f} "
                f"output_bytes={output_bytes}",
                flush=True,
            )
        if elapsed < 6:
            _update_job_stage(job_id, "detecting_face", 0.18)
            continue
        # FaceFusion does not expose exact per-frame progress here, so keep a
        # conservative synthetic estimate that tells the client the real phase.
        progress = min(0.85, 0.25 + (elapsed - 6) / 90 * 0.55)
        _update_job_stage(job_id, "swapping_frame", progress)


def _preprocess_target_video(target_path: Path) -> Path:
    """Downscale/FPS-limit large target videos before FaceFusion to reduce frame work."""
    if not FF_OPTIMIZE_TARGET_VIDEO or not shutil.which("ffmpeg"):
        return target_path

    optimized_path = target_path.with_name(f"{target_path.stem}_optimized.mp4")
    vf = _codec_safe_video_filter()
    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(target_path),
        "-vf", vf,
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "28",
        "-c:a", "aac",
        "-b:a", "96k",
        "-movflags", "+faststart",
        str(optimized_path),
    ]
    started_at = time.perf_counter()
    original_size = target_path.stat().st_size if target_path.exists() else 0
    print(
        f"[video-preprocess] start file={target_path.name} bytes={original_size} "
        f"profile={FF_VIDEO_PROFILE} max_width={FF_TARGET_MAX_WIDTH} fps={FF_TARGET_FPS} "
        f"timeout_seconds={FF_PREPROCESS_TIMEOUT_SECONDS}",
        flush=True,
    )
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=FF_PREPROCESS_TIMEOUT_SECONDS)
        elapsed = time.perf_counter() - started_at
        if result.returncode == 0 and optimized_path.exists() and optimized_path.stat().st_size > 0:
            optimized_size = optimized_path.stat().st_size
            if _video_has_readable_resolution(optimized_path):
                print(
                    f"[video-preprocess] done file={target_path.name} original_bytes={original_size} "
                    f"optimized_bytes={optimized_size} elapsed_seconds={elapsed:.2f}",
                    flush=True,
                )
                return optimized_path
            print(
                f"[video-preprocess] invalid_output_fallback file={target_path.name} "
                f"optimized_bytes={optimized_size} elapsed_seconds={elapsed:.2f}",
                flush=True,
            )
            try:
                optimized_path.unlink(missing_ok=True)
            except Exception:
                pass
            return target_path
        print(
            f"[video-preprocess] skipped file={target_path.name} exit={result.returncode} "
            f"elapsed_seconds={elapsed:.2f} stderr_tail={result.stderr[-500:]}",
            flush=True,
        )
    except subprocess.TimeoutExpired as exc:
        print(
            f"[video-preprocess] timeout file={target_path.name} "
            f"elapsed_seconds={time.perf_counter() - started_at:.2f} "
            f"timeout_seconds={FF_PREPROCESS_TIMEOUT_SECONDS}; using original target",
            flush=True,
        )
    except Exception as exc:
        print(f"[video-preprocess] skipped file={target_path.name} error={exc}", flush=True)

    try:
        optimized_path.unlink(missing_ok=True)
    except Exception:
        pass
    return target_path


def _codec_safe_video_filter() -> str:
    """Build a fast filter that keeps result videos Android-decoder friendly.

    Some Android MediaCodec implementations can fail to initialize otherwise
    valid H.264 streams when dimensions are not macroblock-aligned. The previous
    fast profile often produced 540x304, which ffprobe considered valid but the
    Huawei test device failed to preview. Align both dimensions to 16 before
    FaceFusion generates the final result.
    """
    return (
        f"scale='if(gt(iw,ih),min({FF_TARGET_MAX_WIDTH},iw),-2)':"
        f"'if(gt(iw,ih),-2,min({FF_TARGET_MAX_WIDTH},ih))':flags=fast_bilinear,"
        "scale='max(16,trunc(iw/16)*16)':'max(16,trunc(ih/16)*16)':flags=fast_bilinear,"
        f"fps={FF_TARGET_FPS}"
    )


def _runtime_diagnostics() -> dict:
    """Collect lightweight runtime diagnostics that help identify FC GPU/provider issues."""
    diagnostics: dict = {}
    try:
        result = subprocess.run(
            [FF_PYTHON, "-c", "import onnxruntime as ort, json; print(json.dumps(ort.get_available_providers()))"],
            cwd=FF_DIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        diagnostics["onnxruntime_providers_exit"] = result.returncode
        diagnostics["onnxruntime_providers"] = (result.stdout or result.stderr).strip()[-1000:]
    except Exception as exc:
        diagnostics["onnxruntime_providers_error"] = str(exc)

    try:
        result = subprocess.run(
            [FF_PYTHON, "-c", "import onnxruntime as ort; print(ort.get_device())"],
            cwd=FF_DIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        diagnostics["onnxruntime_device_exit"] = result.returncode
        diagnostics["onnxruntime_device"] = (result.stdout or result.stderr).strip()[-1000:]
    except Exception as exc:
        diagnostics["onnxruntime_device_error"] = str(exc)

    nvidia_smi = shutil.which("nvidia-smi")
    diagnostics["nvidia_smi_path"] = nvidia_smi
    if nvidia_smi:
        try:
            result = subprocess.run(
                [nvidia_smi, "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            diagnostics["nvidia_smi_exit"] = result.returncode
            diagnostics["nvidia_smi"] = (result.stdout or result.stderr).strip()[-1000:]
        except Exception as exc:
            diagnostics["nvidia_smi_error"] = str(exc)
    return diagnostics


def _copy_audio_from_target(target_path: Path, swapped_path: Path) -> Path:
    """Copy the original target audio track into FaceFusion's silent video output."""
    final_path = swapped_path.with_name(f"{swapped_path.stem}_audio{swapped_path.suffix}")
    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(swapped_path),
        "-i", str(target_path),
        "-map", "0:v:0",
        "-map", "1:a?",
        "-c:v", "copy",
        "-c:a", "aac",
        "-shortest",
        "-movflags", "+faststart",
        str(final_path),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if result.returncode == 0 and final_path.exists() and final_path.stat().st_size > 0:
            return final_path
    except Exception:
        pass
    return swapped_path


def _video_duration_seconds(video_path: Path) -> float:
    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(video_path),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        if result.returncode == 0:
            return max(0.1, float(result.stdout.strip()))
    except Exception:
        pass
    return 1.0


def _read_first_frame_with_cv2(video_path: Path, frame_path: Path) -> tuple[float, float]:
    """Extract the first frame with OpenCV in a killable child process.

    FC GPU containers previously hung inside OpenCV/FFmpeg native video decode.
    Running the decode in a separate process lets the API fail fast and fall back
    instead of leaving the job stuck forever in `detecting_face`.
    """
    script = r'''
import json
import sys
from pathlib import Path
import cv2
video_path = Path(sys.argv[1])
frame_path = Path(sys.argv[2])
capture = cv2.VideoCapture(str(video_path))
try:
    if not capture.isOpened():
        raise RuntimeError("OpenCV could not open target video")
    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0.0)
    frame_count = float(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0.0)
    ok, frame = capture.read()
    if not ok or frame is None:
        raise RuntimeError("OpenCV could not read first target frame")
    frame_path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(frame_path), frame):
        raise RuntimeError("OpenCV could not write first target frame")
    duration = frame_count / fps if fps > 0 and frame_count > 0 else 1.0
    print(json.dumps({"duration": min(max(duration, 0.1), 60.0), "fps": max(fps, 1.0)}))
finally:
    capture.release()
'''
    try:
        result = subprocess.run(
            [FF_PYTHON, "-c", script, str(video_path), str(frame_path)],
            cwd=FF_DIR,
            capture_output=True,
            text=True,
            timeout=FF_STATIC_FRAME_DECODE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"OpenCV first-frame extraction timed out after {FF_STATIC_FRAME_DECODE_TIMEOUT_SECONDS}s"
        ) from exc
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "OpenCV first-frame extraction failed").strip()[-1000:])
    try:
        payload = json.loads(result.stdout.strip().splitlines()[-1])
        duration = float(payload["duration"])
        fps = float(payload["fps"])
    except Exception as exc:
        raise RuntimeError(f"OpenCV first-frame extraction returned invalid output: {result.stdout[-1000:]}") from exc
    if not frame_path.exists() or frame_path.stat().st_size <= 0:
        raise RuntimeError("OpenCV first-frame extraction produced an empty image")
    return duration, fps


def _encode_static_frame_video_with_cv2(frame_path: Path, output_path: Path, duration: float) -> None:
    """Encode a repeated still frame as Android-preview-compatible H.264 MP4.

    The first FC MVP used OpenCV's `mp4v` writer. That file is valid MP4, but
    Huawei/Android MediaCodec failed to preview it in `video_player` with
    `video/mp4v-es`. Use ffmpeg/libx264 + yuv420p so the App result dialog can
    preview the generated video instead of only saving it to the gallery.
    """
    if not frame_path.exists() or frame_path.stat().st_size <= 0:
        raise RuntimeError("Static frame encoder received an empty swapped frame")
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg is required for Android-compatible static video encoding")

    fps = max(1.0, float(FF_OUTPUT_VIDEO_FPS or 12))
    safe_duration = max(0.1, float(duration))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-loop", "1",
        "-framerate", f"{fps:g}",
        "-t", f"{safe_duration:.3f}",
        "-i", str(frame_path),
        "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "23",
        "-pix_fmt", "yuv420p",
        "-r", f"{fps:g}",
        "-movflags", "+faststart",
        str(output_path),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=max(30, int(safe_duration) + 60))
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("ffmpeg static video encoding timed out") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "ffmpeg static video encoding failed").strip()[-1000:]
        raise RuntimeError(f"ffmpeg static video encoding failed: {detail}")
    if not output_path.exists() or output_path.stat().st_size <= 0:
        raise RuntimeError("ffmpeg static video encoder produced an empty MP4")


def _run_static_first_frame_video_swap(job_id: str, src_path: Path, prepared_tgt_path: Path, raw_out_path: Path) -> Path:
    """MVP video engine: swap the first target frame, then repeat it as a short MP4.

    Native FaceFusion video mode has hung in FC GPU. This path keeps the Android
    API contract while restoring visible face-swap output: extract one frame from
    the uploaded target video, run the proven image swap path on that frame, and
    encode the swapped still frame back into an MP4 with the target audio copied
    when possible.
    """
    work_dir = raw_out_path.parent / f"{raw_out_path.stem}_static_first_frame"
    work_dir.mkdir(parents=True, exist_ok=True)
    target_frame_path = work_dir / "target_first_frame.jpg"
    swapped_frame_path = work_dir / "swapped_first_frame.jpg"

    _update_job_stage(job_id, "detecting_face", 0.20)
    try:
        duration, source_fps = _read_first_frame_with_cv2(prepared_tgt_path, target_frame_path)
        print(
            f"[video-job:{job_id}] static_first_frame_extracted "
            f"duration_seconds={duration:.3f} source_fps={source_fps:.3f} frame={target_frame_path.name}",
            flush=True,
        )
    except Exception as exc:
        duration = _video_duration_seconds(prepared_tgt_path)
        source_fps = float(FF_OUTPUT_VIDEO_FPS or 12)
        shutil.copyfile(src_path, target_frame_path)
        print(
            f"[video-job:{job_id}] static_first_frame_extract_failed_using_source_frame "
            f"error={exc} duration_seconds={duration:.3f} frame={target_frame_path.name}",
            flush=True,
        )

    _update_job_stage(job_id, "swapping_frame", 0.45)
    exit_code, stdout, stderr = _run_facefusion([
        "--source-paths", str(src_path),
        "--target-path", str(target_frame_path),
        "--output-path", str(swapped_frame_path),
        "--processors", FF_PROCESSORS,
        "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
        "--face-detector-model", FF_FACE_DETECTOR_MODEL,
        "--face-landmarker-model", FF_FACE_LANDMARKER_MODEL,
        "--execution-providers", FF_EXECUTION_PROVIDERS,
    ], timeout=FF_FACEFUSION_TIMEOUT_SECONDS)
    if exit_code != 0 or not swapped_frame_path.exists() or swapped_frame_path.stat().st_size <= 0:
        error_detail = stderr.strip() or stdout.strip() or "Unknown error"
        raise RuntimeError(f"Static first-frame face swap failed: {error_detail}")

    _update_job_stage(job_id, "encoding", 0.82)
    _encode_static_frame_video_with_cv2(swapped_frame_path, raw_out_path, duration)
    final_path = _copy_audio_from_target(prepared_tgt_path, raw_out_path)
    if not final_path.exists() or final_path.stat().st_size <= 0:
        raise RuntimeError("Static first-frame encoder produced an empty MP4")
    print(
        f"[video-job:{job_id}] static_first_frame_done "
        f"output_bytes={final_path.stat().st_size}",
        flush=True,
    )
    return final_path


def _run_frame_by_frame_video_swap(job_id: str, src_path: Path, prepared_tgt_path: Path, raw_out_path: Path) -> Path:
    """Frame-by-frame engine: ffmpeg extract → per-frame image swap → ffmpeg merge.

    This bypasses FaceFusion's native video headless-run which hangs in FC GPU.
    Each frame is processed independently via the proven image swap path, and the
    final result is assembled with ffmpeg (which is confirmed working in FC).
    """
    work_dir = raw_out_path.parent / f"{raw_out_path.stem}_frame_by_frame"
    work_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = work_dir / "frames"
    swapped_dir = work_dir / "swapped"
    frames_dir.mkdir(parents=True, exist_ok=True)
    swapped_dir.mkdir(parents=True, exist_ok=True)

    fps = max(1.0, float(FF_OUTPUT_VIDEO_FPS or 12))
    max_width = int(FF_TARGET_MAX_WIDTH or 360)
    quality = int(FF_OUTPUT_VIDEO_QUALITY or 50)

    # Step 1: Extract frames with ffmpeg.
    # FC GPU container sometimes cannot read files written to /tmp via HTTP upload
    # (ffprobe/ffmpeg hang), while files under FF_TEMP_PATH work fine. Copy the
    # target video to FF_TEMP_PATH first to stay on the reliable filesystem.
    safe_tgt_path = Path(FF_TEMP_PATH) / f"fbf_target_{job_id[:12]}{prepared_tgt_path.suffix}"
    if prepared_tgt_path != safe_tgt_path and not safe_tgt_path.exists():
        shutil.copy2(prepared_tgt_path, safe_tgt_path)
        print(
            f"[video-job:{job_id}] frame_by_frame_copied_to_safe "
            f"from={prepared_tgt_path} ({prepared_tgt_path.stat().st_size} bytes) "
            f"to={safe_tgt_path} ({safe_tgt_path.stat().st_size} bytes)",
            flush=True,
        )
    else:
        safe_tgt_path = prepared_tgt_path

    _update_job_stage(job_id, "detecting_face", 0.20)
    extract_started = time.perf_counter()
    print(
        f"[video-job:{job_id}] frame_by_frame_extract_start fps={fps} max_width={max_width} "
        f"safe_tgt={safe_tgt_path}",
        flush=True,
    )
    # ── inline diagnostics: can Python read the file? ──
    diag_lines = []
    py_head_hex = ""
    try:
        with open(safe_tgt_path, "rb") as _f:
            head = _f.read(160)
        py_head_hex = head[:80].hex()
        diag_lines.append(f"py_read ok={len(head)==160} hex={py_head_hex}")
    except Exception as _e:
        diag_lines.append(f"py_read FAILED: {_e}")
    # ── can we dd the file? ──
    dd_hex = ""
    try:
        dd_result = subprocess.run(
            ["dd", f"if={safe_tgt_path}", "bs=160", "count=1", "status=none"],
            capture_output=True, timeout=10,
        )
        dd_hex = dd_result.stdout[:80].hex()
        diag_lines.append(f"dd ok rc={dd_result.returncode} bytes={len(dd_result.stdout)} hex={dd_hex}")
    except Exception as _e:
        diag_lines.append(f"dd FAILED: {_e}")
    # ── cv2 video validation (ffprobe hangs on FC GPU; cv2.VideoCapture works) ──
    try:
        cap = cv2.VideoCapture(str(safe_tgt_path))
        if cap.isOpened():
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            fps_v = cap.get(cv2.CAP_PROP_FPS)
            frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            cap.release()
            diag_lines.append(f"cv2 ok {width}x{height} fps={fps_v:.2f} frames={frames}")
        else:
            cap.release()
            diag = "; ".join(diag_lines)
            raise RuntimeError(
                f"cv2.VideoCapture cannot open video | diag=[{diag}] "
                f"file={safe_tgt_path} bytes={safe_tgt_path.stat().st_size if safe_tgt_path.exists() else -1}"
            )
    except RuntimeError:
        raise
    except Exception as _e:
        diag = "; ".join(diag_lines)
        raise RuntimeError(
            f"cv2.VideoCapture failed: {_e} | diag=[{diag}] "
            f"file={safe_tgt_path} bytes={safe_tgt_path.stat().st_size if safe_tgt_path.exists() else -1}"
        )

    # Extract frames in an isolated child process. On FC GPU, cv2.VideoCapture
    # can open the upload but cv2.read() may still hang forever; subprocess
    # timeout keeps the API worker recoverable and returns actionable diagnostics.
    cv2_extract_code = r'''
import json
import sys
from pathlib import Path

import cv2

video_path = Path(sys.argv[1])
frames_dir = Path(sys.argv[2])
target_fps = float(sys.argv[3])
max_width = int(sys.argv[4])
cap = cv2.VideoCapture(str(video_path))
if not cap.isOpened():
    print(json.dumps({"ok": False, "error": "cv2 open failed"}))
    raise SystemExit(2)
source_fps = cap.get(cv2.CAP_PROP_FPS) or target_fps or 1.0
frame_interval = max(1, round(source_fps / target_fps)) if target_fps > 0 else 1
frame_index = 0
saved_frames = 0
try:
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_index % frame_interval == 0:
            height, width = frame.shape[:2]
            if width > max_width:
                scale = max_width / float(width)
                frame = cv2.resize(frame, (max_width, max(2, int(height * scale) // 2 * 2)))
            saved_frames += 1
            out_path = frames_dir / f"frame_{saved_frames:06d}.png"
            if not cv2.imwrite(str(out_path), frame):
                print(json.dumps({"ok": False, "error": f"write failed: {out_path}", "frames_read": frame_index, "frames_saved": saved_frames}))
                raise SystemExit(3)
        frame_index += 1
finally:
    cap.release()
print(json.dumps({"ok": True, "source_fps": source_fps, "target_fps": target_fps, "interval": frame_interval, "frames_read": frame_index, "frames_saved": saved_frames}))
'''
    try:
        extract_result = subprocess.run(
            [sys.executable, "-c", cv2_extract_code, str(safe_tgt_path), str(frames_dir), str(fps), str(max_width)],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"cv2 frame extraction child timed out after 120s "
            f"target_bytes={safe_tgt_path.stat().st_size if safe_tgt_path.exists() else -1} "
            f"stdout_tail={(exc.stdout or '')[-300:]} stderr_tail={(exc.stderr or '')[-300:]}"
        )
    if extract_result.returncode != 0:
        raise RuntimeError(
            f"cv2 frame extraction child failed rc={extract_result.returncode} "
            f"stdout_tail={extract_result.stdout[-500:]} stderr_tail={extract_result.stderr[-500:]}"
        )
    try:
        extract_stats = json.loads(extract_result.stdout.strip().splitlines()[-1])
    except Exception as _e:
        raise RuntimeError(
            f"cv2 frame extraction produced invalid stats: {_e} "
            f"stdout_tail={extract_result.stdout[-500:]} stderr_tail={extract_result.stderr[-500:]}"
        )
    if not extract_stats.get("ok"):
        raise RuntimeError(f"cv2 frame extraction failed: {extract_stats}")
    print(
        f"[video-job:{job_id}] frame_by_frame_cv2_extract_done "
        f"source_fps={float(extract_stats.get('source_fps') or 0):.3f} "
        f"target_fps={float(extract_stats.get('target_fps') or 0):.3f} "
        f"interval={extract_stats.get('interval')} "
        f"frames_read={extract_stats.get('frames_read')} frames_saved={extract_stats.get('frames_saved')}",
        flush=True,
    )

    frame_files = sorted(frames_dir.glob("frame_*.png"))
    total_frames = len(frame_files)
    if total_frames == 0:
        raise RuntimeError("No frames extracted from target video")
    print(
        f"[video-job:{job_id}] frame_by_frame_extract_done frames={total_frames} "
        f"elapsed_seconds={time.perf_counter() - extract_started:.2f}",
        flush=True,
    )

    # Step 2: Swap each frame via FaceFusion image swap
    _update_job_stage(job_id, "swapping_frame", 0.25)
    swap_started = time.perf_counter()
    success_count = 0
    last_progress_update = time.perf_counter()

    for i, frame_path in enumerate(frame_files):
        if _get_job(job_id).get("status") == "cancelled":
            raise RuntimeError("Job cancelled during frame-by-frame processing")

        swapped_path = swapped_dir / f"swapped_{i:06d}.jpg"
        exit_code, stdout, stderr = _run_facefusion([
            "--source-paths", str(src_path),
            "--target-path", str(frame_path),
            "--output-path", str(swapped_path),
            "--processors", FF_PROCESSORS,
            "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
            "--face-detector-model", FF_FACE_DETECTOR_MODEL,
            "--face-landmarker-model", FF_FACE_LANDMARKER_MODEL,
            "--execution-providers", FF_EXECUTION_PROVIDERS,
        ], timeout=120)

        if exit_code == 0 and swapped_path.exists() and swapped_path.stat().st_size > 0:
            success_count += 1
        else:
            # Fallback: use original frame
            shutil.copyfile(frame_path, swapped_path)

        # Update progress periodically
        now = time.perf_counter()
        if now - last_progress_update >= 3 or i == total_frames - 1:
            pct = 0.25 + (i + 1) / total_frames * 0.60  # 25% → 85%
            last_progress_update = now
            _update_job_stage(job_id, "swapping_frame", pct)
            print(
                f"[video-job:{job_id}] frame_by_frame_progress frame={i+1}/{total_frames} "
                f"success={success_count} elapsed_seconds={now - swap_started:.1f}",
                flush=True,
            )

    swap_elapsed = time.perf_counter() - swap_started
    print(
        f"[video-job:{job_id}] frame_by_frame_swap_done frames={total_frames} "
        f"success={success_count} elapsed_seconds={swap_elapsed:.1f}",
        flush=True,
    )

    # Step 3: Merge frames + audio back to MP4
    _update_job_stage(job_id, "encoding", 0.88)
    merge_started = time.perf_counter()
    swapped_pattern = swapped_dir / "swapped_%06d.jpg"
    merge_cmd = [
        "ffmpeg", "-y",
        "-framerate", f"{fps:g}",
        "-i", str(swapped_pattern),
        "-i", str(safe_tgt_path),
        "-map", "0:v:0",
        "-map", "1:a?",
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", str(max(18, 51 - quality // 2)),
        "-pix_fmt", "yuv420p",
        "-r", f"{fps:g}",
        "-shortest",
        "-movflags", "+faststart",
        str(raw_out_path),
    ]
    try:
        result = subprocess.run(merge_cmd, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        raise RuntimeError("Frame merge timed out after 300s")
    if result.returncode != 0 or not raw_out_path.exists() or raw_out_path.stat().st_size <= 0:
        raise RuntimeError(f"Frame merge failed: {result.stderr[-500:]}")
    print(
        f"[video-job:{job_id}] frame_by_frame_merge_done "
        f"output_bytes={raw_out_path.stat().st_size} "
        f"elapsed_seconds={time.perf_counter() - merge_started:.2f}",
        flush=True,
    )

    # Copy audio from target
    final_path = _copy_audio_from_target(prepared_tgt_path, raw_out_path)
    # Cleanup work dir
    try:
        shutil.rmtree(work_dir, ignore_errors=True)
    except Exception:
        pass

    print(
        f"[video-job:{job_id}] frame_by_frame_done "
        f"output_bytes={final_path.stat().st_size if final_path.exists() else 0} "
        f"total_elapsed={time.perf_counter() - extract_started:.1f}",
        flush=True,
    )
    return final_path


def _run_video_swap(job_id: str, src_path: Path, tgt_path: Path, raw_out_path: Path) -> Path:
    _update_job_stage(job_id, "preprocessing", 0.08)
    print(
        f"[video-job:{job_id}] preprocess_start source_bytes={src_path.stat().st_size if src_path.exists() else 0} "
        f"target_bytes={tgt_path.stat().st_size if tgt_path.exists() else 0}",
        flush=True,
    )
    preprocess_started_at = time.perf_counter()
    if FF_VIDEO_ENGINE in ("static_first_frame", "frame_by_frame"):
        # Static fallback and frame-by-frame do their own video handling.
        # Frame-by-frame does scaling in its own ffmpeg extract step, so
        # skip the separate preprocessing ffmpeg pass to avoid double-ffmpeg
        # pipeline issues in FC.
        prepared_tgt_path = tgt_path
        print(
            f"[video-job:{job_id}] preprocess_skipped engine={FF_VIDEO_ENGINE} "
            f"target={prepared_tgt_path.name} target_bytes={prepared_tgt_path.stat().st_size if prepared_tgt_path.exists() else 0}",
            flush=True,
        )
    else:
        prepared_tgt_path = _preprocess_target_video(tgt_path)
        print(
            f"[video-job:{job_id}] preprocess_done elapsed_seconds={time.perf_counter() - preprocess_started_at:.2f} "
            f"prepared_target={prepared_tgt_path.name} prepared_bytes={prepared_tgt_path.stat().st_size if prepared_tgt_path.exists() else 0}",
            flush=True,
        )
    _update_job_stage(job_id, "detecting_face", 0.18)
    if FF_VIDEO_ENGINE == "static_first_frame":
        print(
            f"[video-job:{job_id}] static_first_frame_fallback_start profile={FF_VIDEO_PROFILE} "
            f"output_fps={FF_OUTPUT_VIDEO_FPS}",
            flush=True,
        )
        return _run_static_first_frame_video_swap(job_id, src_path, prepared_tgt_path, raw_out_path)

    if FF_VIDEO_ENGINE == "frame_by_frame":
        return _run_frame_by_frame_video_swap(job_id, src_path, prepared_tgt_path, raw_out_path)

    started_at = time.perf_counter()
    print(
        f"[video-job:{job_id}] facefusion_start model={FF_FACE_SWAPPER_MODEL} providers={FF_EXECUTION_PROVIDERS} "
        f"profile={FF_VIDEO_PROFILE} output_fps={FF_OUTPUT_VIDEO_FPS} quality={FF_OUTPUT_VIDEO_QUALITY}",
        flush=True,
    )
    exit_code, stdout, stderr = _run_facefusion([
        "--source-paths", str(src_path),
        "--target-path", str(prepared_tgt_path),
        "--output-path", str(raw_out_path),
        "--processors", FF_PROCESSORS,
        "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
        "--face-detector-model", FF_FACE_DETECTOR_MODEL,
        "--face-landmarker-model", FF_FACE_LANDMARKER_MODEL,
        "--execution-providers", FF_EXECUTION_PROVIDERS,
        "--execution-thread-count", FF_EXECUTION_THREAD_COUNT,
        "--temp-path", FF_TEMP_PATH,
        "--video-memory-strategy", FF_VIDEO_MEMORY_STRATEGY,
        "--output-video-preset", FF_OUTPUT_VIDEO_PRESET,
        "--output-video-quality", FF_OUTPUT_VIDEO_QUALITY,
        "--output-video-fps", FF_OUTPUT_VIDEO_FPS,
        "--log-level", FF_LOG_LEVEL,
    ], timeout=FF_FACEFUSION_TIMEOUT_SECONDS, job_id=job_id, output_path=raw_out_path)
    print(f"[video-job:{job_id}] facefusion_done elapsed_seconds={time.perf_counter() - started_at:.2f} exit={exit_code}", flush=True)

    if exit_code != 0 or not raw_out_path.exists():
        error_detail = stderr.strip() or stdout.strip() or "Unknown error"
        raise RuntimeError(f"Video face swap failed: {error_detail}")

    _update_job_stage(job_id, "encoding", 0.92)
    try:
        return _copy_audio_from_target(prepared_tgt_path, raw_out_path)
    finally:
        if prepared_tgt_path != tgt_path:
            try:
                prepared_tgt_path.unlink(missing_ok=True)
            except Exception:
                pass


def _process_video_job(job_id: str, src_path: Path, tgt_path: Path, raw_out_path: Path) -> None:
    if _get_job(job_id).get("status") == "cancelled":
        return
    _set_job(job_id, status="processing", processing_started_at=time.time(), updated_at=time.time())
    _update_job_stage(job_id, "preprocessing", 0.05)
    started_at = time.perf_counter()
    try:
        final_path = _run_video_swap(job_id, src_path, tgt_path, raw_out_path)
        if _get_job(job_id).get("status") == "cancelled":
            return
        output_key = _persist_job_file(job_id, "output/result.mp4", final_path)
        stdout_key = None
        stderr_key = None
        job_snapshot = _get_job(job_id) or {}
        stdout_path = job_snapshot.get("facefusion_stdout_path")
        stderr_path = job_snapshot.get("facefusion_stderr_path")
        if stdout_path and Path(stdout_path).exists():
            stdout_key = _persist_job_file(job_id, "logs/facefusion_stdout.log", Path(stdout_path))
        if stderr_path and Path(stderr_path).exists():
            stderr_key = _persist_job_file(job_id, "logs/facefusion_stderr.log", Path(stderr_path))
        _set_job(
            job_id,
            status="completed",
            stage="completed",
            stage_label=_STAGE_LABELS["completed"],
            progress=1.0,
            output_path=str(final_path),
            output_key=output_key,
            facefusion_stdout_key=stdout_key,
            facefusion_stderr_key=stderr_key,
            processing_seconds=round(time.perf_counter() - started_at, 3),
            updated_at=time.time(),
        )
    except Exception as exc:
        if _get_job(job_id).get("status") != "cancelled":
            _set_job(job_id, status="failed", stage="failed", stage_label=_STAGE_LABELS["failed"], error=str(exc), updated_at=time.time())
    finally:
        for p in [src_path, tgt_path]:
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass


# ── Endpoints ────────────────────────────────────────────────────────────

@app.get("/api/health")
async def health():
    """Health check — verifies FaceFusion is available."""
    ff_ok = os.path.isfile(FF_PYTHON) and os.path.isdir(FF_DIR)
    return {
        "status": "ok" if ff_ok else "degraded",
        "version": "1.0.0",
        "facefusion_path": FF_DIR,
        "execution_providers": FF_EXECUTION_PROVIDERS,
        "face_swapper_model": FF_FACE_SWAPPER_MODEL,
        "face_detector_model": FF_FACE_DETECTOR_MODEL,
        "face_landmarker_model": FF_FACE_LANDMARKER_MODEL,
        "execution_thread_count": FF_EXECUTION_THREAD_COUNT,
        "temp_path": FF_TEMP_PATH,
        "video_memory_strategy": FF_VIDEO_MEMORY_STRATEGY,
        "video_profile": FF_VIDEO_PROFILE,
        "video_max_workers": VIDEO_MAX_WORKERS,
        "target_max_width": FF_TARGET_MAX_WIDTH,
        "target_fps": FF_TARGET_FPS,
        "output_video_fps": FF_OUTPUT_VIDEO_FPS,
        "output_video_quality": FF_OUTPUT_VIDEO_QUALITY,
        "preprocess_timeout_seconds": FF_PREPROCESS_TIMEOUT_SECONDS,
        "facefusion_timeout_seconds": FF_FACEFUSION_TIMEOUT_SECONDS,
        "facefusion_log_level": FF_LOG_LEVEL,
        "video_engine": FF_VIDEO_ENGINE,
        "video_job_mode": FF_VIDEO_JOB_MODE,
        "job_store": getattr(JOB_STORE, "kind", "disabled"),
        "job_store_enabled": bool(getattr(JOB_STORE, "enabled", False)),
        "runtime_diagnostics": _runtime_diagnostics(),
    }


@app.post("/api/swap/image")
async def swap_image(
    source: UploadFile = File(..., description="Source image (face to use)"),
    target: UploadFile = File(..., description="Target image (face to replace)"),
):
    """
    Swap face in an image.

    - `source`: image containing the face to use (jpg/png)
    - `target`: image containing the face to replace (jpg/png)

    Returns the swapped image (JPEG).
    """
    # Validate inputs
    for f, name in [(source, "source"), (target, "target")]:
        if not f.filename:
            raise HTTPException(400, f"{name} image is required")

    # Save uploads
    src_path, _, _ = _save_upload(source, "src_img")
    tgt_path, _, _ = _save_upload(target, "tgt_img")
    out_path = _make_output_path("img_swap", ".jpg")

    try:
        exit_code, stdout, stderr = _run_facefusion([
            "--source-paths", str(src_path),
            "--target-path", str(tgt_path),
            "--output-path", str(out_path),
            "--processors", FF_PROCESSORS,
            "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
            "--face-detector-model", FF_FACE_DETECTOR_MODEL,
            "--face-landmarker-model", FF_FACE_LANDMARKER_MODEL,
            "--execution-providers", FF_EXECUTION_PROVIDERS,
        ])

        if exit_code != 0 or not out_path.exists():
            error_detail = stderr.strip() or stdout.strip() or "Unknown error"
            raise HTTPException(500, f"Face swap failed: {error_detail}")

        return FileResponse(
            out_path,
            media_type="image/jpeg",
            filename="swapped.jpg",
            headers={"X-Processing-Time": stdout.split("Processing time:")[-1].strip().split("\n")[0] if "Processing time:" in stdout else "unknown"},
        )

    finally:
        # Cleanup inputs (keep output)
        for p in [src_path, tgt_path]:
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass


@app.post("/api/swap/video")
async def swap_video(
    source: UploadFile = File(..., description="Source image with the face to use"),
    target: UploadFile = File(..., description="Target video to swap face into"),
):
    """
    Swap face in a video.

    - `source`: image containing the face to use (jpg/png)
    - `target`: video file to swap face into (mp4/mov/avi)

    Returns the swapped video (MP4).
    """
    for f, name in [(source, "source"), (target, "target")]:
        if not f.filename:
            raise HTTPException(400, f"{name} file is required")

    src_path, _, _ = _save_upload(source, "src_face")
    tgt_path, _, _ = _save_upload(target, "tgt_video")
    out_path = _make_output_path("vid_swap", ".mp4")

    try:
        final_path = _run_video_swap("sync", src_path, tgt_path, out_path)

        return FileResponse(
            final_path,
            media_type="video/mp4",
            filename="swapped.mp4",
        )

    finally:
        for p in [src_path, tgt_path]:
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass


@app.post("/api/swap/video/job")
async def swap_video_job(
    request: Request,
    source: UploadFile = File(..., description="Source image with the face to use"),
    target: UploadFile = File(..., description="Target video to swap face into"),
):
    """Start a server-side video swap job and return immediately.

    Once uploads finish, processing continues on the server even if the Android
    app goes to the background. Clients poll `/api/swap/status/{job_id}` and
    download `/api/swap/result/{job_id}` when complete.
    """
    for f, name in [(source, "source"), (target, "target")]:
        if not f.filename:
            raise HTTPException(400, f"{name} file is required")

    job_id = uuid.uuid4().hex
    upload_debug_id = getattr(request.state, "upload_request_id", "unknown")
    endpoint_started_at = time.perf_counter()
    _upload_log(
        f"[upload:{upload_debug_id}] endpoint_start job_id={job_id} "
        f"source_filename={source.filename} target_filename={target.filename}"
    )
    upload_started_at = time.perf_counter()
    src_path, source_bytes, source_save_seconds = _save_upload(source, "src_face")
    _upload_log(
        f"[upload:{upload_debug_id}] source_saved job_id={job_id} bytes={source_bytes} "
        f"save_seconds={source_save_seconds:.3f}"
    )
    tgt_path, target_bytes, target_save_seconds = _save_upload(target, "tgt_video")
    source_key = _persist_job_file(job_id, "input/source" + src_path.suffix, src_path)
    target_key = _persist_job_file(job_id, "input/target" + tgt_path.suffix, tgt_path)
    _upload_log(
        f"[upload:{upload_debug_id}] target_saved job_id={job_id} bytes={target_bytes} "
        f"save_seconds={target_save_seconds:.3f} throughput_mbps={_throughput_mbps(target_bytes, target_save_seconds):.2f}"
    )
    upload_save_seconds = time.perf_counter() - upload_started_at
    endpoint_seconds = time.perf_counter() - endpoint_started_at
    out_path = _make_output_path(f"vid_swap_{job_id}", ".mp4")
    _set_job(
        job_id,
        status="queued",
        stage="queued",
        stage_label=_STAGE_LABELS["queued"],
        progress=0.0,
        video_profile=FF_VIDEO_PROFILE,
        output_path=None,
        error=None,
        source_bytes=source_bytes,
        target_bytes=target_bytes,
        source_save_seconds=round(source_save_seconds, 3),
        target_save_seconds=round(target_save_seconds, 3),
        upload_save_seconds=round(upload_save_seconds, 3),
        endpoint_seconds=round(endpoint_seconds, 3),
        upload_debug_id=upload_debug_id,
        source_key=source_key,
        target_key=target_key,
        created_at=time.time(),
        updated_at=time.time(),
    )

    if FF_VIDEO_JOB_MODE == "inline":
        _upload_log(
            f"[upload:{upload_debug_id}] job_inline_start job_id={job_id} source_bytes={source_bytes} "
            f"target_bytes={target_bytes} upload_save_seconds={upload_save_seconds:.3f} "
            f"endpoint_seconds={endpoint_seconds:.3f}"
        )
        _process_video_job(job_id, src_path, tgt_path, out_path)
    else:
        VIDEO_JOB_EXECUTOR.submit(_process_video_job, job_id, src_path, tgt_path, out_path)
        _upload_log(
            f"[upload:{upload_debug_id}] job_queued job_id={job_id} source_bytes={source_bytes} "
            f"target_bytes={target_bytes} upload_save_seconds={upload_save_seconds:.3f} "
            f"endpoint_seconds={endpoint_seconds:.3f}"
        )
    job = _get_job(job_id)
    return JSONResponse({
        "job_id": job_id,
        "status": job.get("status", "queued"),
        "stage": job.get("stage", "queued"),
        "stage_label": job.get("stage_label", _STAGE_LABELS["queued"]),
        "progress": job.get("progress", 0.0),
        "video_profile": FF_VIDEO_PROFILE,
        "upload_debug_id": upload_debug_id,
        "source_bytes": source_bytes,
        "target_bytes": target_bytes,
        "upload_save_seconds": round(upload_save_seconds, 3),
        "endpoint_seconds": round(time.perf_counter() - endpoint_started_at, 3),
    })


@app.get("/api/swap/status/{job_id}")
async def swap_status(job_id: str):
    """Check status of a server-side swap job."""
    job = _get_job(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return {
        "job_id": job_id,
        "status": job.get("status"),
        "stage": job.get("stage"),
        "stage_label": job.get("stage_label"),
        "progress": job.get("progress"),
        "video_profile": job.get("video_profile", FF_VIDEO_PROFILE),
        "error": job.get("error"),
        "created_at": job.get("created_at"),
        "updated_at": job.get("updated_at"),
        "source_bytes": job.get("source_bytes"),
        "target_bytes": job.get("target_bytes"),
        "upload_save_seconds": job.get("upload_save_seconds"),
        "source_save_seconds": job.get("source_save_seconds"),
        "target_save_seconds": job.get("target_save_seconds"),
        "endpoint_seconds": job.get("endpoint_seconds"),
        "upload_debug_id": job.get("upload_debug_id"),
        "processing_seconds": job.get("processing_seconds"),
        "facefusion_pid": job.get("facefusion_pid"),
        "facefusion_started_at": job.get("facefusion_started_at"),
        "facefusion_timeout_seconds": job.get("facefusion_timeout_seconds"),
        "facefusion_elapsed_seconds": job.get("facefusion_elapsed_seconds"),
        "facefusion_output_bytes": job.get("facefusion_output_bytes"),
        "facefusion_heartbeat_at": job.get("facefusion_heartbeat_at"),
        "facefusion_cmd": job.get("facefusion_cmd"),
        "facefusion_stdout_tail": job.get("facefusion_stdout_tail"),
        "facefusion_stderr_tail": job.get("facefusion_stderr_tail"),
        "output_key": job.get("output_key"),
        "source_key": job.get("source_key"),
        "target_key": job.get("target_key"),
        "facefusion_stdout_key": job.get("facefusion_stdout_key"),
        "facefusion_stderr_key": job.get("facefusion_stderr_key"),
        "job_store": getattr(JOB_STORE, "kind", "disabled"),
        "status_persisted": bool(getattr(JOB_STORE, "enabled", False)),
    }


@app.post("/api/swap/cancel/{job_id}")
async def cancel_swap_job(job_id: str):
    """Cancel a queued or processing video swap job."""
    job = _get_job(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    status = job.get("status")
    if status in {"completed", "failed", "cancelled"}:
        return {"job_id": job_id, "status": status}

    process = None
    with JOBS_LOCK:
        process = JOB_PROCESSES.get(job_id)
    if process is not None:
        _terminate_process(process)
    _set_job(job_id, status="cancelled", stage="cancelled", stage_label=_STAGE_LABELS["cancelled"], error="Job cancelled by client", updated_at=time.time())
    return {"job_id": job_id, "status": "cancelled"}


@app.get("/api/swap/result/{job_id}")
async def swap_result(job_id: str):
    """Download the completed video swap result."""
    job = _get_job(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    if job.get("status") != "completed":
        raise HTTPException(409, f"Job is not completed: {job.get('status')}")
    output_path = Path(job.get("output_path") or "")
    if output_path.exists():
        return FileResponse(output_path, media_type="video/mp4", filename="swapped.mp4")
    output_key = job.get("output_key")
    if output_key:
        result_bytes = _read_job_store_bytes(job_id, "output/result.mp4")
        if result_bytes:
            return Response(
                content=result_bytes,
                media_type="video/mp4",
                headers={"Content-Disposition": 'attachment; filename="swapped.mp4"'},
            )
    raise HTTPException(404, "Result file not found")


# ── Debug / Diagnostics ─────────────────────────────────────────────────

@app.get("/api/debug/temp-files")
async def debug_temp_files():
    """List files in FF_TEMP_PATH and FF_OUTPUT_DIR for diagnostics."""
    result = {}
    for label, d in [("temp", FF_TEMP_PATH), ("output", FF_OUTPUT_DIR)]:
        p = Path(d)
        if p.exists():
            try:
                items = []
                for f in sorted(p.rglob("*")):
                    if f.is_file():
                        items.append({"path": str(f), "size": f.stat().st_size})
                result[label] = {"dir": str(p), "file_count": len(items), "files": items[:50]}
            except Exception as exc:
                result[label] = {"error": str(exc)}
        else:
            result[label] = {"dir": str(p), "exists": False}
    return result


@app.post("/api/debug/run-facefusion")
async def debug_run_facefusion(request: Request):
    """Run a FaceFusion command directly with short timeout for diagnostics."""
    import asyncio, signal
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(400, "JSON body required")
    args = body.get("args", [])
    timeout = min(int(body.get("timeout", 30)), 120)
    if not args:
        raise HTTPException(400, "args required")

    cmd = [FF_PYTHON, "facefusion.py", "headless-run"] + args
    log_token = uuid.uuid4().hex[:8]
    stdout_path = Path(tempfile.gettempdir()) / f"facefusion_debug_{log_token}_stdout.log"
    stderr_path = Path(tempfile.gettempdir()) / f"facefusion_debug_{log_token}_stderr.log"

    print(f"[debug] run-facefusion cmd={' '.join(cmd)} timeout={timeout}", flush=True)

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=FF_DIR,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout_bytes, stderr_bytes = await asyncio.wait_for(
            proc.communicate(), timeout=timeout
        )
        exit_code = proc.returncode or 0
        stdout_text = stdout_bytes.decode("utf-8", "replace")[-8000:] if stdout_bytes else ""
        stderr_text = stderr_bytes.decode("utf-8", "replace")[-8000:] if stderr_bytes else ""
    except asyncio.TimeoutError:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            await asyncio.sleep(2)
        except Exception:
            pass
        try:
            proc.kill()
            await proc.wait()
        except Exception:
            pass
        exit_code = -1
        stdout_text = ""
        stderr_text = f"TIMEOUT after {timeout}s"

    # Check for output files
    output_files = []
    for d in [FF_OUTPUT_DIR, FF_TEMP_PATH]:
        p = Path(d)
        if p.exists():
            for f in sorted(p.rglob("*"), key=lambda x: x.stat().st_mtime, reverse=True):
                if f.is_file():
                    output_files.append({"path": str(f), "size": f.stat().st_size, "mtime": f.stat().st_mtime})
                    if len(output_files) >= 20:
                        break
        if len(output_files) >= 20:
            break

    return {
        "cmd": " ".join(cmd),
        "exit_code": exit_code,
        "stdout_last_8000": stdout_text,
        "stderr_last_8000": stderr_text,
        "recent_output_files": output_files,
    }


@app.post("/api/debug/facefusion-video-quick")
async def debug_facefusion_video_quick(
    source: UploadFile = File(..., description="Source image with face to use"),
    target: UploadFile = File(..., description="Target video to swap face into"),
    timeout: int = 30,
):
    """Upload files and run FaceFusion directly, returning full results quickly."""
    import asyncio as aio, signal
    timeout = min(timeout, 60)
    # Save uploads
    src_bytes = await source.read()
    tgt_bytes = await target.read()
    src_path = Path(tempfile.gettempdir()) / f"debug_src_{uuid.uuid4().hex[:8]}.jpg"
    tgt_path = Path(tempfile.gettempdir()) / f"debug_tgt_{uuid.uuid4().hex[:8]}.mp4"
    out_path = Path(FF_OUTPUT_DIR) / f"debug_out_{uuid.uuid4().hex[:8]}.mp4"
    src_path.write_bytes(src_bytes)
    tgt_path.write_bytes(tgt_bytes)

    args = [
        "--source-paths", str(src_path),
        "--target-path", str(tgt_path),
        "--output-path", str(out_path),
        "--processors", FF_PROCESSORS,
        "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
        "--face-detector-model", FF_FACE_DETECTOR_MODEL,
        "--face-landmarker-model", FF_FACE_LANDMARKER_MODEL,
        "--execution-providers", FF_EXECUTION_PROVIDERS,
        "--execution-thread-count", FF_EXECUTION_THREAD_COUNT,
        "--temp-path", FF_TEMP_PATH,
        "--video-memory-strategy", FF_VIDEO_MEMORY_STRATEGY,
        "--output-video-preset", FF_OUTPUT_VIDEO_PRESET,
        "--output-video-quality", FF_OUTPUT_VIDEO_QUALITY,
        "--output-video-fps", FF_OUTPUT_VIDEO_FPS,
        "--log-level", "debug",
    ]
    cmd = [FF_PYTHON, "facefusion.py", "headless-run"] + args
    print(f"[debug-quick] start timeout={timeout}", flush=True)

    proc = await aio.create_subprocess_exec(
        *cmd, cwd=FF_DIR,
        stdout=aio.subprocess.PIPE, stderr=aio.subprocess.PIPE,
    )
    try:
        stdout_bytes, stderr_bytes = await aio.wait_for(proc.communicate(), timeout=timeout)
        exit_code = proc.returncode or 0
        stdout_text = (stdout_bytes or b"").decode("utf-8", "replace")[-8000:]
        stderr_text = (stderr_bytes or b"").decode("utf-8", "replace")[-8000:]
    except aio.TimeoutError:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            await aio.sleep(2)
        except Exception:
            pass
        try:
            proc.kill()
            await proc.wait()
        except Exception:
            pass
        exit_code = -1
        stdout_text = ""
        stderr_text = f"TIMEOUT after {timeout}s"

    # Check temp directory for extracted frames
    temp_files = []
    temp_dir = Path(FF_TEMP_PATH)
    if temp_dir.exists():
        for f in sorted(temp_dir.rglob("*"), key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True):
            if f.is_file():
                temp_files.append({"path": str(f), "size": f.stat().st_size})
                if len(temp_files) >= 30:
                    break

    out_exists = out_path.exists()
    out_size = out_path.stat().st_size if out_exists else 0

    # Cleanup
    for p in [src_path, tgt_path]:
        try: p.unlink(missing_ok=True)
        except: pass

    return {
        "exit_code": exit_code,
        "stdout_tail": stdout_text,
        "stderr_tail": stderr_text,
        "output_exists": out_exists,
        "output_size": out_size,
        "temp_dir": str(FF_TEMP_PATH),
        "temp_files": temp_files,
    }



@app.get("/api/debug/ffmpeg-check")
async def debug_ffmpeg_check():
    """Quick ffmpeg diagnostics in the container."""
    import asyncio as aio, shutil
    result = {}
    proc = await aio.create_subprocess_exec(
        "ffmpeg", "-version",
        stdout=aio.subprocess.PIPE, stderr=aio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    result["ffmpeg_version"] = (stdout or stderr or b"").decode("utf-8", "replace").split("\n")[0][:200]
    test_dir = Path(FF_TEMP_PATH) / "ffmpeg_test"
    test_dir.mkdir(parents=True, exist_ok=True)
    proc2 = await aio.create_subprocess_exec(
        "ffmpeg", "-y", "-f", "lavfi", "-i", "color=c=red:size=32x32:d=1", "-r", "1",
        "-t", "1", str(test_dir / "test.mp4"),
        stdout=aio.subprocess.PIPE, stderr=aio.subprocess.PIPE,
    )
    await proc2.communicate()
    proc3 = await aio.create_subprocess_exec(
        "ffmpeg", "-y", "-i", str(test_dir / "test.mp4"),
        "-r", "1", str(test_dir / "test_%03d.png"),
        stdout=aio.subprocess.PIPE, stderr=aio.subprocess.PIPE,
    )
    out3, err3 = await proc3.communicate()
    result["extract_test_exit"] = proc3.returncode
    result["extract_test_stderr"] = (err3 or b"").decode("utf-8", "replace")[-500:]
    frames = sorted(test_dir.glob("test_*.png"))
    result["frames_extracted"] = len(frames)
    result["frame_sizes"] = [f.stat().st_size for f in frames]
    proc4 = await aio.create_subprocess_exec(
        "ffmpeg", "-encoders",
        stdout=aio.subprocess.PIPE, stderr=aio.subprocess.PIPE,
    )
    out4, _ = await proc4.communicate()
    encoders = (out4 or b"").decode("utf-8", "replace")
    for name in ["libx264", "h264_nvenc", "h264_amf"]:
        result[f"has_{name}"] = name in encoders
    try: shutil.rmtree(test_dir)
    except: pass
    return result


@app.post("/api/debug/upload-hex")
async def debug_upload_hex(file: UploadFile = File(...)):
    """Accept a file upload and return the first 200 bytes as hex + MD5."""
    import hashlib
    data = await file.read()
    h = hashlib.sha256(data).hexdigest()
    return {
        "size": len(data),
        "sha256": h,
        "first_200_hex": data[:200].hex(),
        "last_200_hex": data[-200:].hex() if len(data) > 200 else "",
    }


def main():
    print(f"🚀 FaceSwap API server starting on port {API_PORT}")
    print(f"   FaceFusion dir: {FF_DIR}")
    print(f"   Execution providers: {FF_EXECUTION_PROVIDERS}")
    print(f"   Docs: http://localhost:{API_PORT}/docs")
    uvicorn.run(app, host="0.0.0.0", port=API_PORT, log_level="info")


if __name__ == "__main__":
    main()
