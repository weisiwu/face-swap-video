#!/usr/bin/env python3
"""Preflight checks for Aliyun Scheme B: OSS + FC Serverless GPU + ACR.

This script is intentionally safe: it does not call Aliyun APIs or print secrets.
It only checks that local configuration is present enough to start deployment work.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Any


REQUIRED_USER_PROVIDED_ENV = (
    "ALIYUN_ACCESS_KEY_ID",
    "ALIYUN_ACCESS_KEY_SECRET",
    "ALIYUN_REGION_ID",
    "ALIYUN_OSS_BUCKET",
    "ALIYUN_OSS_ENDPOINT",
    "ALIYUN_ACR_REGISTRY",
    "ALIYUN_ACR_NAMESPACE",
    "ALIYUN_ACR_REPOSITORY",
)

OPTIONAL_ENV = (
    "ALIYUN_ACCOUNT_MODE",
    "ALIYUN_ACR_USERNAME",
    "ALIYUN_ACR_PASSWORD",
    "ALIYUN_FC_SERVICE_NAME",
    "ALIYUN_FC_FUNCTION_NAME",
    "ALIYUN_FC_GPU_SPEC",
    "ALIYUN_FC_CUSTOM_DOMAIN",
)

LOCAL_COMMANDS = ("docker", "python3")


@dataclass(frozen=True)
class PreflightReport:
    env: dict[str, str]
    missing_required_env: list[str]
    commands: dict[str, str | None]
    missing_commands: list[str]
    no_sls_required: bool = True
    frontend_unchanged_required: bool = True

    @property
    def ready_for_deploy_scripts(self) -> bool:
        return not self.missing_required_env and not self.missing_commands

    def to_dict(self) -> dict[str, Any]:
        return {
            "ready_for_deploy_scripts": self.ready_for_deploy_scripts,
            "missing_required_env": self.missing_required_env,
            "required_env_summary": safe_env_summary(self.env),
            "commands": self.commands,
            "missing_commands": self.missing_commands,
            "no_sls_required": self.no_sls_required,
            "frontend_unchanged_required": self.frontend_unchanged_required,
            "account_mode": self.env.get("ALIYUN_ACCOUNT_MODE") or "main_account_confirmed_by_user",
            "domain_mode": self.env.get("ALIYUN_FC_CUSTOM_DOMAIN") or "fc_default_domain",
            "user_action_required": user_action_required(self.missing_required_env),
        }


def safe_env_summary(env: Mapping[str, str]) -> dict[str, str]:
    summary: dict[str, str] = {}
    for key in REQUIRED_USER_PROVIDED_ENV + OPTIONAL_ENV:
        value = env.get(key, "").strip()
        if not value:
            summary[key] = "MISSING"
        elif "SECRET" in key or "PASSWORD" in key or key.endswith("KEY_ID"):
            summary[key] = "SET"
        else:
            summary[key] = value
    return summary


def user_action_required(missing: list[str]) -> list[str]:
    actions: list[str] = []
    if "ALIYUN_ACCESS_KEY_ID" in missing or "ALIYUN_ACCESS_KEY_SECRET" in missing:
        actions.append("提供阿里云主账号 AccessKey（当前阶段用户确认可直接使用主账号）。")
    if "ALIYUN_REGION_ID" in missing:
        actions.append("确认 OSS / ACR / FC Serverless GPU 使用的阿里云地域。")
    if "ALIYUN_OSS_BUCKET" in missing or "ALIYUN_OSS_ENDPOINT" in missing:
        actions.append("创建或确认 OSS Bucket、Endpoint，并授权 FC 读写指定前缀。")
    if any(key in missing for key in ("ALIYUN_ACR_REGISTRY", "ALIYUN_ACR_NAMESPACE", "ALIYUN_ACR_REPOSITORY")):
        actions.append("创建或确认 ACR 镜像仓库，确保本机可 push、FC 可 pull。")
    return actions


def load_preflight(env: Mapping[str, str] | None = None) -> PreflightReport:
    source = dict(os.environ if env is None else env)
    values = {key: source.get(key, "").strip() for key in REQUIRED_USER_PROVIDED_ENV + OPTIONAL_ENV}
    missing_env = [key for key in REQUIRED_USER_PROVIDED_ENV if not values.get(key)]
    commands = {cmd: shutil.which(cmd) for cmd in LOCAL_COMMANDS}
    missing_commands = [cmd for cmd, path in commands.items() if not path]
    return PreflightReport(
        env=values,
        missing_required_env=missing_env,
        commands=commands,
        missing_commands=missing_commands,
    )


def check_frontend_unchanged(base_ref: str = "main") -> list[str]:
    """Return changed app frontend files compared with base_ref.

    Empty list means this scheme-B branch currently has not changed Android app UI/source files.
    """
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{base_ref}...HEAD"],
        capture_output=True,
        text=True,
        check=True,
    )
    changed = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return [path for path in changed if path.startswith("app/lib/") or path.startswith("app/test/")]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Preflight Aliyun Scheme B local configuration.")
    parser.add_argument("--output", default="")
    parser.add_argument("--check-frontend", action="store_true")
    parser.add_argument("--base-ref", default="main")
    args = parser.parse_args(argv)

    report = load_preflight().to_dict()
    if args.check_frontend:
        report["changed_frontend_files"] = check_frontend_unchanged(args.base_ref)
        report["frontend_unchanged"] = not report["changed_frontend_files"]

    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if report["ready_for_deploy_scripts"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
