"""Bind an explicitly selected local process to reviewed source/model inputs."""

import argparse
import json
from pathlib import Path
from uuid import uuid4

from navcore.cli._benchmark_inputs import build_input_identity, process_identity, validate_api_url
from navcore.cli.bundle import file_sha256, read_json
from navcore.vision.artifacts import verify_artifacts


def receipt(
    backend: Path,
    model_dir: Path,
    api_url: str,
    pid: int,
    profile: str,
    traces: list[Path],
    smoke_path: Path | None,
):
    if profile not in {"cpu", "cuda:0"} or pid <= 0:
        raise ValueError("Invalid local server process profile")
    artifacts = verify_artifacts(model_dir.absolute())
    process = process_identity(pid)
    command = (Path("/proc") / str(pid) / "cmdline").read_bytes()
    if b"uvicorn" not in command or b"navcore.app:create_app" not in command:
        raise ValueError("Selected process is not the navigation application factory")
    result = {
        "schema_version": 1,
        "attestation_kind": "operator_local",
        "server_instance_id": str(uuid4()),
        "api_url": validate_api_url(api_url),
        "profile": profile,
        "adapter_kind": "real_models",
        "inputs": build_input_identity(backend, model_dir),
        "process": process,
        "environment": {"profile": profile},
        "limitations": ["Local operator attestation; not cryptographic remote identity"],
    }
    if traces:
        if smoke_path is None:
            raise ValueError("Trace attribution requires real model smoke evidence")
        smoke = read_json(smoke_path)
        if (
            smoke.get("adapter_kind") != "real_models"
            or smoke.get("encoder_fingerprint") != artifacts.encoder_fingerprint
        ):
            raise ValueError("Smoke evidence does not match the encoder")
        result["attestation"] = {
            "kind": "local_run",
            "model_smoke_verified": True,
            "trace_sha256": sorted(file_sha256(path) for path in traces),
            "model_smoke_sha256": file_sha256(smoke_path),
        }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--profile", choices=("cpu", "cuda:0"), required=True)
    parser.add_argument("--trace", type=Path, action="append", default=[])
    parser.add_argument("--model-smoke-report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = receipt(
        args.backend,
        args.model_dir,
        args.api_url,
        args.pid,
        args.profile,
        args.trace,
        args.model_smoke_report,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as output:
        output.write(json.dumps(result, indent=2, allow_nan=False) + "\n")
