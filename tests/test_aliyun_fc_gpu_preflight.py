import importlib.util
import sys
from pathlib import Path


def load_module():
    script = Path(__file__).resolve().parents[1] / "scripts" / "aliyun_fc_gpu_preflight.py"
    spec = importlib.util.spec_from_file_location("aliyun_fc_gpu_preflight", script)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_preflight_reports_user_owned_missing_prerequisites_without_secrets():
    mod = load_module()
    report = mod.load_preflight(env={}).to_dict()

    assert report["ready_for_deploy_scripts"] is False
    assert "ALIYUN_ACCESS_KEY_ID" in report["missing_required_env"]
    assert "ALIYUN_ACCESS_KEY_SECRET" in report["missing_required_env"]
    assert report["required_env_summary"]["ALIYUN_ACCESS_KEY_SECRET"] == "MISSING"
    assert report["no_sls_required"] is True
    assert report["frontend_unchanged_required"] is True
    assert any("RAM" in action or "AccessKey" in action for action in report["user_action_required"])


def test_safe_env_summary_masks_secret_values():
    mod = load_module()
    summary = mod.safe_env_summary(
        {
            "ALIYUN_ACCESS_KEY_ID": "ak",
            "ALIYUN_ACCESS_KEY_SECRET": "secret",
            "ALIYUN_ACR_PASSWORD": "pwd",
            "ALIYUN_REGION_ID": "cn-shanghai",
        }
    )

    assert summary["ALIYUN_ACCESS_KEY_ID"] == "SET"
    assert summary["ALIYUN_ACCESS_KEY_SECRET"] == "SET"
    assert summary["ALIYUN_ACR_PASSWORD"] == "SET"
    assert summary["ALIYUN_REGION_ID"] == "cn-shanghai"


def test_ready_when_required_env_and_commands_exist(monkeypatch):
    mod = load_module()
    env = {key: "value" for key in mod.REQUIRED_USER_PROVIDED_ENV}
    monkeypatch.setattr(mod.shutil, "which", lambda command: f"/usr/bin/{command}")

    report = mod.load_preflight(env=env)

    assert report.ready_for_deploy_scripts is True
    assert report.missing_required_env == []
    assert report.missing_commands == []
