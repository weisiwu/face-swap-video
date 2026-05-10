#!/usr/bin/env python3
"""FaceFusion REST API server — provides clean endpoints for the Android app."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────────
API_PORT = int(os.environ.get("API_PORT", "8765"))
FF_PYTHON = "/opt/miniconda3/envs/facefusion/bin/python"
FF_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # server/
FF_EXECUTION_PROVIDERS = os.environ.get("FF_EXECUTION_PROVIDERS", "coreml")
FF_PROCESSORS = os.environ.get("FF_PROCESSORS", "face_swapper")
FF_FACE_SWAPPER_MODEL = os.environ.get("FF_FACE_SWAPPER_MODEL", "inswapper_128_fp16")
OUTPUT_BASE = Path(os.environ.get("FF_OUTPUT_DIR", os.path.join(FF_DIR, ".api_output")))
OUTPUT_BASE.mkdir(parents=True, exist_ok=True)

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
        exit_code, stdout, stderr = _run_facefusion([
            "--source-paths", str(src_path),
            "--target-path", str(tgt_path),
            "--output-path", str(out_path),
            "--processors", FF_PROCESSORS,
            "--face-swapper-model", FF_FACE_SWAPPER_MODEL,
            "--execution-providers", FF_EXECUTION_PROVIDERS,
        ], timeout=1800)  # video can take longer

        if exit_code != 0 or not out_path.exists():
            error_detail = stderr.strip() or stdout.strip() or "Unknown error"
            raise HTTPException(500, f"Video face swap failed: {error_detail}")

        return FileResponse(
            out_path,
            media_type="video/mp4",
            filename="swapped.mp4",
        )

    finally:
        for p in [src_path, tgt_path]:
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass


@app.get("/api/swap/status/{job_id}")
async def swap_status(job_id: str):
    """Check status of a swap job (placeholder for async processing)."""
    return {"job_id": job_id, "status": "completed"}


# ── Main ─────────────────────────────────────────────────────────────────

def main():
    print(f"🚀 FaceSwap API server starting on port {API_PORT}")
    print(f"   FaceFusion dir: {FF_DIR}")
    print(f"   Execution providers: {FF_EXECUTION_PROVIDERS}")
    print(f"   Docs: http://localhost:{API_PORT}/docs")
    uvicorn.run(app, host="0.0.0.0", port=API_PORT, log_level="info")


if __name__ == "__main__":
    main()
