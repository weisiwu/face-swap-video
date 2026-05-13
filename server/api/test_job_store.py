import json
import sys
from pathlib import Path
from types import SimpleNamespace

from job_store import LocalJobStore, OssJobStore, create_job_store_from_env


class FakeOssObject:
    def __init__(self, data: bytes):
        self._data = data

    def read(self) -> bytes:
        return self._data


class FakeOssBucket:
    def __init__(self):
        self.objects: dict[str, bytes] = {}

    def put_object(self, key: str, data):
        if hasattr(data, "read"):
            data = data.read()
        if isinstance(data, str):
            data = data.encode("utf-8")
        self.objects[key] = bytes(data)

    def get_object(self, key: str):
        if key not in self.objects:
            raise FileNotFoundError(key)
        return FakeOssObject(self.objects[key])


def test_local_job_store_persists_and_loads_status(tmp_path: Path):
    store = LocalJobStore(tmp_path, prefix="jobs")
    store.save_status("job-1", {"job_id": "job-1", "status": "queued", "progress": 0.1})

    assert store.load_status("job-1") == {"job_id": "job-1", "status": "queued", "progress": 0.1}
    status_path = tmp_path / "jobs" / "job-1" / "status.json"
    assert json.loads(status_path.read_text(encoding="utf-8"))["status"] == "queued"


def test_local_job_store_persists_bytes_and_files(tmp_path: Path):
    store = LocalJobStore(tmp_path, prefix="jobs")
    source_key = store.save_bytes("job-1", "input/source.jpg", b"source-bytes")
    log_path = tmp_path / "stderr.log"
    log_path.write_text("stderr text", encoding="utf-8")
    log_key = store.save_file("job-1", "logs/stderr.log", log_path)

    assert source_key == "jobs/job-1/input/source.jpg"
    assert log_key == "jobs/job-1/logs/stderr.log"
    assert store.read_bytes("job-1", "input/source.jpg") == b"source-bytes"
    assert store.read_text("job-1", "logs/stderr.log") == "stderr text"


def test_create_job_store_from_env_disabled_by_default(tmp_path: Path, monkeypatch):
    monkeypatch.delenv("OSS_JOB_STORE_ENABLED", raising=False)
    monkeypatch.setenv("LOCAL_JOB_STORE_DIR", str(tmp_path))

    store = create_job_store_from_env()

    assert store.enabled is False
    assert store.kind == "disabled"


def test_create_job_store_from_env_local_when_explicit(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("OSS_JOB_STORE_ENABLED", "local")
    monkeypatch.setenv("LOCAL_JOB_STORE_DIR", str(tmp_path))
    monkeypatch.setenv("OSS_JOB_PREFIX", "face-swap-video/jobs")

    store = create_job_store_from_env()
    store.save_status("job-2", {"job_id": "job-2", "status": "completed"})

    assert store.enabled is True
    assert store.kind == "local"
    assert store.load_status("job-2")["status"] == "completed"


def test_oss_job_store_persists_status_and_artifacts(tmp_path: Path):
    bucket = FakeOssBucket()
    store = OssJobStore(bucket, prefix="face-swap-video/jobs")
    output = tmp_path / "result.mp4"
    output.write_bytes(b"mp4-bytes")

    status_key = store.save_status("job-3", {"job_id": "job-3", "status": "completed"})
    source_key = store.save_bytes("job-3", "input/source.jpg", b"source")
    result_key = store.save_file("job-3", "output/result.mp4", output)

    assert status_key == "face-swap-video/jobs/job-3/status.json"
    assert source_key == "face-swap-video/jobs/job-3/input/source.jpg"
    assert result_key == "face-swap-video/jobs/job-3/output/result.mp4"
    assert store.load_status("job-3")["status"] == "completed"
    assert store.read_bytes("job-3", "input/source.jpg") == b"source"
    assert store.read_bytes("job-3", "output/result.mp4") == b"mp4-bytes"


def test_create_job_store_from_env_oss_when_configured(monkeypatch):
    created = {}

    def fake_bucket(auth, endpoint, bucket_name):
        created["auth"] = auth
        created["endpoint"] = endpoint
        created["bucket_name"] = bucket_name
        return FakeOssBucket()

    fake_oss2 = SimpleNamespace(
        Auth=lambda access_key_id, access_key_secret: (access_key_id, access_key_secret),
        Bucket=fake_bucket,
    )
    monkeypatch.setitem(sys.modules, "oss2", fake_oss2)
    monkeypatch.setenv("OSS_JOB_STORE_ENABLED", "1")
    monkeypatch.setenv("ALIYUN_ACCESS_KEY_ID", "ak")
    monkeypatch.setenv("ALIYUN_ACCESS_KEY_SECRET", "sk")
    monkeypatch.setenv("ALIYUN_OSS_ENDPOINT", "oss-cn-shanghai.aliyuncs.com")
    monkeypatch.setenv("ALIYUN_OSS_BUCKET", "bucket")
    monkeypatch.setenv("OSS_JOB_PREFIX", "face-swap-video/jobs")

    store = create_job_store_from_env()

    assert store.enabled is True
    assert store.kind == "oss"
    assert created == {
        "auth": ("ak", "sk"),
        "endpoint": "oss-cn-shanghai.aliyuncs.com",
        "bucket_name": "bucket",
    }
