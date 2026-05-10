#!/usr/bin/env python3
"""FaceFusion REST API server — provides clean endpoints for the Android app."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from datetime import datetime
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────────
API_PORT = int(os.environ.get("API_PORT", "9999"))
FF_PYTHON = "/opt/miniconda3/envs/facefusion/bin/python"
FF_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # server/
FF_EXECUTION_PROVIDERS = os.environ.get("FF_EXECUTION_PROVIDERS", "coreml")
FF_PROCESSORS = os.environ.get("FF_PROCESSORS", "face_swapper")
FF_FACE_SWAPPER_MODEL = os.environ.get("FF_FACE_SWAPPER_MODEL", "inswapper_128_fp16")
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


def _save_upload(upload: UploadFile, prefix: str) -> Path:
    """Save an uploaded file to a temp location, return its path."""
    suffix = Path(upload.filename or "file").suffix or ".bin"
    out = Path(tempfile.gettempdir()) / f"{prefix}_{uuid.uuid4().hex[:8]}{suffix}"
    with open(out, "wb") as f:
        content = upload.file.read()
        f.write(content)
    return out


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
    exit_code, stdout, stderr = _run_facefusion([
        "--source-paths", str(src_path),
        "--target-path", str(tgt_path),
        "--output-path", str(raw_out_path),
        "--processors", FF_PROCESSORS,
        "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
        "--execution-providers", FF_EXECUTION_PROVIDERS,
    ], timeout=1800)

    if exit_code != 0 or not raw_out_path.exists():
        error_detail = stderr.strip() or stdout.strip() or "Unknown error"
        raise RuntimeError(f"Video face swap failed: {error_detail}")

    return _copy_audio_from_target(tgt_path, raw_out_path)


def _process_video_job(job_id: str, src_path: Path, tgt_path: Path, raw_out_path: Path) -> None:
    _set_job(job_id, status="processing", updated_at=time.time())
    try:
        final_path = _run_video_swap(src_path, tgt_path, raw_out_path)
        _set_job(job_id, status="completed", output_path=str(final_path), updated_at=time.time())
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
    src_path = _save_upload(source, "src_img")
    tgt_path = _save_upload(target, "tgt_img")
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

    src_path = _save_upload(source, "src_face")
    tgt_path = _save_upload(target, "tgt_video")
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
    src_path = _save_upload(source, "src_face")
    tgt_path = _save_upload(target, "tgt_video")
    out_path = _make_output_path(f"vid_swap_{job_id}", ".mp4")
    _set_job(job_id, status="queued", output_path=None, error=None, created_at=time.time(), updated_at=time.time())

    thread = threading.Thread(
        target=_process_video_job,
        args=(job_id, src_path, tgt_path, out_path),
        daemon=True,
    )
    thread.start()
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
