"""External job persistence for the FaceFusion API.

The API keeps an in-memory job map for fast same-instance polling, but FC can
restart, freeze, or route later requests to another instance. This module gives
video jobs an optional external store so status/log/result recovery does not
depend on one Python process.
"""

from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol


class JobStore(Protocol):
    kind: str
    enabled: bool

    def save_status(self, job_id: str, status: dict[str, Any]) -> str | None:
        ...

    def load_status(self, job_id: str) -> dict[str, Any] | None:
        ...

    def save_bytes(self, job_id: str, relative_key: str, data: bytes) -> str | None:
        ...

    def save_file(self, job_id: str, relative_key: str, file_path: str | Path) -> str | None:
        ...

    def read_bytes(self, job_id: str, relative_key: str) -> bytes | None:
        ...

    def read_text(self, job_id: str, relative_key: str) -> str | None:
        ...


@dataclass
class DisabledJobStore:
    kind: str = "disabled"
    enabled: bool = False

    def save_status(self, job_id: str, status: dict[str, Any]) -> str | None:
        return None

    def load_status(self, job_id: str) -> dict[str, Any] | None:
        return None

    def save_bytes(self, job_id: str, relative_key: str, data: bytes) -> str | None:
        return None

    def save_file(self, job_id: str, relative_key: str, file_path: str | Path) -> str | None:
        return None

    def read_bytes(self, job_id: str, relative_key: str) -> bytes | None:
        return None

    def read_text(self, job_id: str, relative_key: str) -> str | None:
        return None


class OssJobStore:
    kind = "oss"
    enabled = True

    def __init__(self, bucket: Any, prefix: str = "jobs") -> None:
        self.bucket = bucket
        self.prefix = _normalize_prefix(prefix)

    def save_status(self, job_id: str, status: dict[str, Any]) -> str:
        key = self._object_key(job_id, "status.json")
        self.bucket.put_object(key, json.dumps(status, ensure_ascii=False, sort_keys=True).encode("utf-8"))
        return key

    def load_status(self, job_id: str) -> dict[str, Any] | None:
        key = self._object_key(job_id, "status.json")
        try:
            obj = self.bucket.get_object(key)
            data = obj.read()
            if isinstance(data, bytes):
                data = data.decode("utf-8", "replace")
            return json.loads(data)
        except Exception:
            return None

    def save_bytes(self, job_id: str, relative_key: str, data: bytes) -> str:
        key = self._object_key(job_id, relative_key)
        self.bucket.put_object(key, data)
        return key

    def save_file(self, job_id: str, relative_key: str, file_path: str | Path) -> str:
        key = self._object_key(job_id, relative_key)
        with Path(file_path).open("rb") as f:
            self.bucket.put_object(key, f)
        return key

    def read_bytes(self, job_id: str, relative_key: str) -> bytes | None:
        key = self._object_key(job_id, relative_key)
        try:
            data = self.bucket.get_object(key).read()
            if isinstance(data, str):
                return data.encode("utf-8")
            return bytes(data)
        except Exception:
            return None

    def read_text(self, job_id: str, relative_key: str) -> str | None:
        data = self.read_bytes(job_id, relative_key)
        if data is None:
            return None
        return data.decode("utf-8", "replace")

    def _object_key(self, job_id: str, relative_key: str) -> str:
        safe_key = _normalize_relative_key(relative_key)
        return f"{self.prefix}/{job_id}/{safe_key}"


class LocalJobStore:
    kind = "local"
    enabled = True

    def __init__(self, base_dir: str | Path, prefix: str = "jobs") -> None:
        self.base_dir = Path(base_dir)
        self.prefix = _normalize_prefix(prefix)
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def save_status(self, job_id: str, status: dict[str, Any]) -> str:
        return self._write_json(job_id, "status.json", status)

    def load_status(self, job_id: str) -> dict[str, Any] | None:
        path = self._path_for(job_id, "status.json")
        if not path.exists():
            return None
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None

    def save_bytes(self, job_id: str, relative_key: str, data: bytes) -> str:
        path = self._path_for(job_id, relative_key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return self._object_key(job_id, relative_key)

    def save_file(self, job_id: str, relative_key: str, file_path: str | Path) -> str:
        path = self._path_for(job_id, relative_key)
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(file_path, path)
        return self._object_key(job_id, relative_key)

    def read_bytes(self, job_id: str, relative_key: str) -> bytes | None:
        path = self._path_for(job_id, relative_key)
        if not path.exists():
            return None
        return path.read_bytes()

    def read_text(self, job_id: str, relative_key: str) -> str | None:
        data = self.read_bytes(job_id, relative_key)
        if data is None:
            return None
        return data.decode("utf-8", "replace")

    def _write_json(self, job_id: str, relative_key: str, payload: dict[str, Any]) -> str:
        path = self._path_for(job_id, relative_key)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = path.with_suffix(path.suffix + ".tmp")
        tmp_path.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
        tmp_path.replace(path)
        return self._object_key(job_id, relative_key)

    def _path_for(self, job_id: str, relative_key: str) -> Path:
        safe_key = _normalize_relative_key(relative_key)
        return self.base_dir / self.prefix / job_id / safe_key

    def _object_key(self, job_id: str, relative_key: str) -> str:
        safe_key = _normalize_relative_key(relative_key)
        return f"{self.prefix}/{job_id}/{safe_key}"


def create_job_store_from_env() -> JobStore:
    mode = os.environ.get("OSS_JOB_STORE_ENABLED", "0").strip().lower()
    prefix = os.environ.get("OSS_JOB_PREFIX", "jobs")
    if mode in {"1", "true", "yes", "oss"}:
        access_key_id = os.environ.get("ALIYUN_ACCESS_KEY_ID", "").strip()
        access_key_secret = os.environ.get("ALIYUN_ACCESS_KEY_SECRET", "").strip()
        endpoint = os.environ.get("ALIYUN_OSS_ENDPOINT", "").strip()
        bucket_name = os.environ.get("ALIYUN_OSS_BUCKET", "").strip()
        if not all([access_key_id, access_key_secret, endpoint, bucket_name]):
            return DisabledJobStore()
        try:
            import oss2  # type: ignore

            auth = oss2.Auth(access_key_id, access_key_secret)
            bucket = oss2.Bucket(auth, endpoint, bucket_name)
            return OssJobStore(bucket, prefix=prefix)
        except Exception as exc:
            print(f"[job-store] oss_init_failed error={exc}", flush=True)
            return DisabledJobStore()
    if mode == "local":
        base_dir = os.environ.get("LOCAL_JOB_STORE_DIR", os.path.join(os.getcwd(), ".job_store"))
        return LocalJobStore(base_dir, prefix=prefix)
    return DisabledJobStore()


def _normalize_prefix(prefix: str) -> str:
    cleaned = prefix.strip().strip("/")
    return cleaned or "jobs"


def _normalize_relative_key(relative_key: str) -> str:
    cleaned = relative_key.strip().lstrip("/")
    if not cleaned or ".." in Path(cleaned).parts:
        raise ValueError(f"Invalid job store key: {relative_key!r}")
    return cleaned
