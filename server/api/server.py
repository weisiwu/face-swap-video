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

# ── Config ──────────────────────────────────────────────────────────────
API_PORT = int(os.environ.get("API_PORT", "9999"))
FF_PYTHON = "/opt/miniconda3/envs/facefusion/bin/python"
FF_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # server/
FF_EXECUTION_PROVIDERS = os.environ.get("FF_EXECUTION_PROVIDERS", "coreml")
FF_PROCESSORS = os.environ.get("FF_PROCESSORS", "face_swapper")
FF_FACE_SWAPPER_MODEL = os.environ.get("FF_FACE_SWAPPER_MODEL", "inswapper_128_fp16")
FF_EXECUTION_THREAD_COUNT = os.environ.get("FF_EXECUTION_THREAD_COUNT", "4")
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
JOBS: dict[str, dict] = {}
JOB_PROCESSES: dict[str, subprocess.Popen] = {}
JOBS_LOCK = threading.Lock()
VIDEO_JOB_EXECUTOR = ThreadPoolExecutor(max_workers=VIDEO_MAX_WORKERS, thread_name_prefix="facefusion-video")

# ── App ─────────────────────────────────────────────────────────────────
try:
    from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import FileResponse, JSONResponse
    import uvicorn
except ImportError:
    print("Installing dependencies...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "fastapi", "uvicorn", "python-multipart", "-q"])
    from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import FileResponse, JSONResponse
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


def _run_facefusion(args: list[str], timeout: int = 600, job_id: str | None = None) -> tuple[int, str, str]:
    """Run FaceFusion headless-run and return (exit_code, stdout, stderr)."""
    cmd = [FF_PYTHON, "facefusion.py", "headless-run"] + args
    process = subprocess.Popen(
        cmd,
        cwd=FF_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    if job_id:
        with JOBS_LOCK:
            JOB_PROCESSES[job_id] = process
    stop_stage_tracker: threading.Event | None = None
    stage_thread: threading.Thread | None = None
    if job_id:
        stop_stage_tracker = threading.Event()
        stage_thread = threading.Thread(
            target=_track_facefusion_stage,
            args=(job_id, stop_stage_tracker),
            daemon=True,
        )
        stage_thread.start()
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        return process.returncode, stdout, stderr
    except subprocess.TimeoutExpired:
        _terminate_process(process)
        stdout, stderr = process.communicate()
        return 124, stdout, stderr or "FaceFusion timed out"
    finally:
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


def _set_job(job_id: str, **values) -> None:
    with JOBS_LOCK:
        current = JOBS.setdefault(job_id, {})
        current.update(values)


def _get_job(job_id: str) -> dict | None:
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        return dict(job) if job else None


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


def _track_facefusion_stage(job_id: str, stop_event: threading.Event) -> None:
    started_at = time.perf_counter()
    while not stop_event.wait(3):
        if _get_job(job_id).get("status") == "cancelled":
            return
        elapsed = time.perf_counter() - started_at
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
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if result.returncode == 0 and optimized_path.exists() and optimized_path.stat().st_size > 0:
            original_size = target_path.stat().st_size if target_path.exists() else 0
            optimized_size = optimized_path.stat().st_size
            print(
                f"[video-preprocess] {target_path.name}: {original_size} -> {optimized_size} bytes "
                f"in {time.perf_counter() - started_at:.2f}s",
                flush=True,
            )
            return optimized_path
        print(f"[video-preprocess] skipped: {result.stderr[-500:]}", flush=True)
    except Exception as exc:
        print(f"[video-preprocess] skipped: {exc}", flush=True)

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


def _run_video_swap(job_id: str, src_path: Path, tgt_path: Path, raw_out_path: Path) -> Path:
    _update_job_stage(job_id, "preprocessing", 0.08)
    prepared_tgt_path = _preprocess_target_video(tgt_path)
    _update_job_stage(job_id, "detecting_face", 0.18)
    started_at = time.perf_counter()
    exit_code, stdout, stderr = _run_facefusion([
        "--source-paths", str(src_path),
        "--target-path", str(prepared_tgt_path),
        "--output-path", str(raw_out_path),
        "--processors", FF_PROCESSORS,
        "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
        "--execution-providers", FF_EXECUTION_PROVIDERS,
        "--execution-thread-count", FF_EXECUTION_THREAD_COUNT,
        "--output-video-preset", FF_OUTPUT_VIDEO_PRESET,
        "--output-video-quality", FF_OUTPUT_VIDEO_QUALITY,
        "--output-video-fps", FF_OUTPUT_VIDEO_FPS,
        "--log-level", "warn",
    ], timeout=1800, job_id=job_id)
    print(f"[video-swap] facefusion finished in {time.perf_counter() - started_at:.2f}s exit={exit_code}", flush=True)

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
        _set_job(
            job_id,
            status="completed",
            stage="completed",
            stage_label=_STAGE_LABELS["completed"],
            progress=1.0,
            output_path=str(final_path),
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
        "video_profile": FF_VIDEO_PROFILE,
        "video_max_workers": VIDEO_MAX_WORKERS,
        "target_max_width": FF_TARGET_MAX_WIDTH,
        "target_fps": FF_TARGET_FPS,
        "output_video_fps": FF_OUTPUT_VIDEO_FPS,
        "output_video_quality": FF_OUTPUT_VIDEO_QUALITY,
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
        created_at=time.time(),
        updated_at=time.time(),
    )

    VIDEO_JOB_EXECUTOR.submit(_process_video_job, job_id, src_path, tgt_path, out_path)
    _upload_log(
        f"[upload:{upload_debug_id}] job_queued job_id={job_id} source_bytes={source_bytes} "
        f"target_bytes={target_bytes} upload_save_seconds={upload_save_seconds:.3f} "
        f"endpoint_seconds={endpoint_seconds:.3f}"
    )
    return JSONResponse({
        "job_id": job_id,
        "status": "queued",
        "stage": "queued",
        "stage_label": _STAGE_LABELS["queued"],
        "progress": 0.0,
        "video_profile": FF_VIDEO_PROFILE,
        "upload_debug_id": upload_debug_id,
        "source_bytes": source_bytes,
        "target_bytes": target_bytes,
        "upload_save_seconds": round(upload_save_seconds, 3),
        "endpoint_seconds": round(endpoint_seconds, 3),
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
    if not output_path.exists():
        raise HTTPException(404, "Result file not found")
    return FileResponse(output_path, media_type="video/mp4", filename="swapped.mp4")


# ── Main ─────────────────────────────────────────────────────────────────

def main():
    print(f"🚀 FaceSwap API server starting on port {API_PORT}")
    print(f"   FaceFusion dir: {FF_DIR}")
    print(f"   Execution providers: {FF_EXECUTION_PROVIDERS}")
    print(f"   Docs: http://localhost:{API_PORT}/docs")
    uvicorn.run(app, host="0.0.0.0", port=API_PORT, log_level="info")


if __name__ == "__main__":
    main()
