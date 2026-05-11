#!/usr/bin/env python3
"""FaceFusion REST API server — provides clean endpoints for the Android app."""

import hashlib
import json
import os
import shutil
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
FF_OUTPUT_VIDEO_PRESET = os.environ.get("FF_OUTPUT_VIDEO_PRESET", "ultrafast")
FF_OUTPUT_VIDEO_QUALITY = os.environ.get("FF_OUTPUT_VIDEO_QUALITY", "70")
FF_OUTPUT_VIDEO_FPS = os.environ.get("FF_OUTPUT_VIDEO_FPS", "24")
FF_OPTIMIZE_TARGET_VIDEO = os.environ.get("FF_OPTIMIZE_TARGET_VIDEO", "1") != "0"
FF_TARGET_MAX_WIDTH = int(os.environ.get("FF_TARGET_MAX_WIDTH", "720"))
FF_TARGET_FPS = int(os.environ.get("FF_TARGET_FPS", "24"))
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
JOBS_LOCK = threading.Lock()
VIDEO_JOB_EXECUTOR = ThreadPoolExecutor(max_workers=1, thread_name_prefix="facefusion-video")

# ── App ─────────────────────────────────────────────────────────────────
try:
    from fastapi import FastAPI, File, Form, UploadFile, HTTPException
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import FileResponse, JSONResponse
    import uvicorn
except ImportError:
    print("Installing dependencies...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "fastapi", "uvicorn", "python-multipart", "-q"])
    from fastapi import FastAPI, File, Form, UploadFile, HTTPException
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

# ── Helpers ──────────────────────────────────────────────────────────────

def _run_facefusion(args: list[str], timeout: int = 600) -> tuple[int, str, str]:
    """Run FaceFusion headless-run and return (exit_code, stdout, stderr)."""
    cmd = [FF_PYTHON, "facefusion.py", "headless-run"] + args
    result = subprocess.run(
        cmd,
        cwd=FF_DIR,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return result.returncode, result.stdout, result.stderr


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



def _preprocess_target_video(target_path: Path) -> Path:
    """Downscale/FPS-limit large target videos before FaceFusion to reduce frame work."""
    if not FF_OPTIMIZE_TARGET_VIDEO or not shutil.which("ffmpeg"):
        return target_path

    optimized_path = target_path.with_name(f"{target_path.stem}_optimized.mp4")
    vf = (
        f"scale='if(gt(iw,ih),min({FF_TARGET_MAX_WIDTH},iw),-2)':"
        f"'if(gt(iw,ih),-2,min({FF_TARGET_MAX_WIDTH},ih))':flags=fast_bilinear,"
        f"fps={FF_TARGET_FPS}"
    )
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


def _run_video_swap(src_path: Path, tgt_path: Path, raw_out_path: Path) -> Path:
    prepared_tgt_path = _preprocess_target_video(tgt_path)
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
    ], timeout=1800)
    print(f"[video-swap] facefusion finished in {time.perf_counter() - started_at:.2f}s exit={exit_code}", flush=True)

    if exit_code != 0 or not raw_out_path.exists():
        error_detail = stderr.strip() or stdout.strip() or "Unknown error"
        raise RuntimeError(f"Video face swap failed: {error_detail}")

    try:
        return _copy_audio_from_target(prepared_tgt_path, raw_out_path)
    finally:
        if prepared_tgt_path != tgt_path:
            try:
                prepared_tgt_path.unlink(missing_ok=True)
            except Exception:
                pass


def _process_video_job(job_id: str, src_path: Path, tgt_path: Path, raw_out_path: Path) -> None:
    _set_job(job_id, status="processing", processing_started_at=time.time(), updated_at=time.time())
    started_at = time.perf_counter()
    try:
        final_path = _run_video_swap(src_path, tgt_path, raw_out_path)
        _set_job(
            job_id,
            status="completed",
            output_path=str(final_path),
            processing_seconds=round(time.perf_counter() - started_at, 3),
            updated_at=time.time(),
        )
    except Exception as exc:
        _set_job(job_id, status="failed", error=str(exc), updated_at=time.time())
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
        final_path = _run_video_swap(src_path, tgt_path, out_path)

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
    upload_started_at = time.perf_counter()
    src_path, source_bytes, source_save_seconds = _save_upload(source, "src_face")
    tgt_path, target_bytes, target_save_seconds = _save_upload(target, "tgt_video")
    upload_save_seconds = time.perf_counter() - upload_started_at
    out_path = _make_output_path(f"vid_swap_{job_id}", ".mp4")
    _set_job(
        job_id,
        status="queued",
        output_path=None,
        error=None,
        source_bytes=source_bytes,
        target_bytes=target_bytes,
        source_save_seconds=round(source_save_seconds, 3),
        target_save_seconds=round(target_save_seconds, 3),
        upload_save_seconds=round(upload_save_seconds, 3),
        created_at=time.time(),
        updated_at=time.time(),
    )

    VIDEO_JOB_EXECUTOR.submit(_process_video_job, job_id, src_path, tgt_path, out_path)
    return JSONResponse({"job_id": job_id, "status": "queued"})


@app.get("/api/swap/status/{job_id}")
async def swap_status(job_id: str):
    """Check status of a server-side swap job."""
    job = _get_job(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return {
        "job_id": job_id,
        "status": job.get("status"),
        "error": job.get("error"),
        "created_at": job.get("created_at"),
        "updated_at": job.get("updated_at"),
        "source_bytes": job.get("source_bytes"),
        "target_bytes": job.get("target_bytes"),
        "upload_save_seconds": job.get("upload_save_seconds"),
        "processing_seconds": job.get("processing_seconds"),
    }


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
