"""T11 network replay benchmark; never upgrades independent G0-G4 evidence.

Required inputs supplement the plan's abbreviated command: --route-id UUID,
--frames-jsonl prepared replay metadata, and --model-dir verified artifacts.
Frame JSONL rows are {sample_index,pts_ms,relative_path,pixel_sha256}; the bounded
dataset loops, and each challenge causes a fresh decode and JPEG quality75 encode.
This is replay of recorded pixels, not a live camera or independent pilot trial.

--server-receipt is a local operator attestation, not a network identity endpoint:
{"schema_version":1,"attestation_kind":"operator_local","server_instance_id":"UUID",
 "api_url":"http://127.0.0.1:8095","profile":"cpu","adapter_kind":"real_models",
 "inputs":{source_sha256,uv_lock_sha256,model_manifest_sha256,policy_sha256},
 "process": process_identity(pid),
 "workload":{"route_id":"UUID","checkpoint_count":4,"reference_counts":[3,3,3,3],
             "route_fingerprint":"SHA256"}}.
Use _benchmark_inputs.build_input_identity and process_identity to produce the
exact hashes. A matched receipt only establishes the operator's source/process
claim; an absent or mismatched receipt blocks performance acceptance.
"""

import argparse
import asyncio
import json
import os
import platform
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import httpx

from navcore.cli._benchmark_inputs import (
    FrameDataset,
    build_input_identity,
    check_attestation,
    load_devices,
    source_identity,
)
from navcore.cli._benchmark_metrics import Metrics, performance_decision
from navcore.cli._benchmark_transport import (
    ResourceSampler,
    ping_health,
    run_stream,
    sample_resources,
)
from navcore.vision.artifacts import ArtifactError, file_sha256, verify_artifacts


def _seconds(value: str) -> float:
    number = float(value)
    if not 0 <= number <= 1800 or not number < float("inf"):
        raise argparse.ArgumentTypeError("Seconds must be finite and within 0..1800")
    return number


def _pid(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("Backend PID must be positive")
    return number


def register_benchmark(commands) -> None:
    parser = commands.add_parser(
        "benchmark",
        help="Measure actual HTTP/WS replay without claiming pilot acceptance",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--device-env-dir", type=Path, required=True)
    parser.add_argument("--sessions", type=int, choices=(1, 4), required=True)
    parser.add_argument("--route-id", type=UUID, required=True)
    parser.add_argument("--frames-jsonl", type=Path, required=True)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--warmup-seconds", type=_seconds, default=30)
    parser.add_argument("--duration-seconds", type=_seconds, default=300)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--profile", choices=("cpu", "cuda:0"), default="cpu")
    parser.add_argument("--backend-pid", type=_pid)
    parser.add_argument("--server-receipt", type=Path)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--dataset-manifest", type=Path)


async def benchmark(args) -> dict:
    if args.duration_seconds <= 0:
        raise ValueError("Measurement duration must be positive")
    devices = load_devices(args.device_env_dir, args.sessions)
    dataset = FrameDataset.load(args.frames_jsonl)
    inputs = build_input_identity(args.source_root, args.model_dir, args.dataset_manifest)
    inputs.update(
        {
            "frames_jsonl_sha256": dataset.jsonl_sha256,
            "prepared_source_manifest_sha256": dataset.source_manifest_sha256,
        }
    )
    attestation = check_attestation(
        args.server_receipt,
        inputs,
        devices[0].api_url,
        args.profile,
        args.backend_pid,
    )
    artifacts_verified, encoder_fingerprint = False, None
    try:
        artifacts = await asyncio.to_thread(verify_artifacts, args.model_dir.absolute())
        artifacts_verified, encoder_fingerprint = True, artifacts.encoder_fingerprint
    except (ArtifactError, OSError):
        pass
    sampler = ResourceSampler(args.backend_pid)
    stats = Metrics(time.monotonic(), args.warmup_seconds, args.duration_seconds, args.sessions)
    completed = False
    sessions = []
    checkpoint_counts = []
    stop = asyncio.Event()
    started = asyncio.Event()
    monitors = []

    async def monitor_after_start(function, *values):
        await started.wait()
        await function(*values)

    async with httpx.AsyncClient(
        base_url=devices[0].api_url,
        timeout=3,
        follow_redirects=False,
        trust_env=False,
    ) as http:
        try:
            for device in devices:
                response = await http.post(
                    "/v1/sessions",
                    json={
                        "route_id": str(args.route_id),
                        "sensor": {"mode": "rgb"},
                        "language": "vi-VN",
                    },
                    headers={"Authorization": f"Bearer {device.token}"},
                )
                if response.status_code != 201:
                    raise ValueError("Session creation failed")
                session = response.json()
                identity = str(UUID(session["id"]))
                sessions.append((identity, device))
                checkpoint_counts.append(session.get("checkpoint_count"))
                if session.get("stream_path") != f"/v1/sessions/{identity}/stream":
                    raise ValueError("Invalid session stream identity")
            stats = Metrics(
                float("inf"),
                args.warmup_seconds,
                args.duration_seconds,
                args.sessions,
            )
            monitors = [
                asyncio.create_task(monitor_after_start(ping_health, http, stats, stop)),
                asyncio.create_task(monitor_after_start(sample_resources, sampler, stats, stop)),
            ]
            barrier = asyncio.Barrier(args.sessions)
            outcomes = await asyncio.gather(
                *(
                    run_stream({"id": identity}, device, dataset, stats, barrier, started)
                    for identity, device in sessions
                )
            )
            completed = all(outcomes) and time.monotonic() >= stats.measurement_end
        except (httpx.HTTPError, OSError, ValueError, KeyError, TypeError):
            stats.errors["http_or_setup_failure"] += 1
        finally:
            stop.set()
            if monitors:
                if not started.is_set():
                    for task in monitors:
                        task.cancel()
                results = await asyncio.gather(*monitors, return_exceptions=True)
                if any(isinstance(result, Exception) for result in results):
                    stats.errors["monitor_failure"] += 1
            stats.finish_pending(time.monotonic())
            for identity, device in sessions:
                try:
                    response = await http.delete(
                        f"/v1/sessions/{identity}",
                        headers={"Authorization": f"Bearer {device.token}"},
                    )
                    if response.status_code != 204:
                        stats.errors["session_cleanup_failure"] += 1
                except (httpx.HTTPError, OSError):
                    stats.errors["session_cleanup_failure"] += 1
    summary = stats.summary()
    if (
        source_identity(args.source_root) != inputs["source_sha256"]
        or file_sha256(args.frames_jsonl) != inputs["frames_jsonl_sha256"]
    ):
        attestation = {
            "status": "BLOCKED_ATTESTATION",
            "adapter_kind": "unverified",
            "reason": "Source or replay metadata changed during measurement",
        }
    attested = attestation["status"] == "MATCHED_OPERATOR_ATTESTATION"
    real_models = attested and artifacts_verified and attestation["adapter_kind"] == "real_models"
    workload = attestation.get("workload")
    standard_route = (
        isinstance(workload, dict)
        and workload.get("route_id") == str(args.route_id)
        and workload.get("checkpoint_count") == 4
        and workload.get("reference_counts") == [3] * 4
        and isinstance(workload.get("route_fingerprint"), str)
        and len(workload["route_fingerprint"]) == 64
        and checkpoint_counts == [4] * args.sessions
    )
    report = {
        "schema_version": 1,
        "run_id": str(uuid4()),
        "created_at": datetime.now(UTC).isoformat(),
        "evidence_kind": "network_replay",
        "adapter_kind": "real_models"
        if real_models
        else (
            "synthetic" if attested and attestation["adapter_kind"] == "synthetic" else "unverified"
        ),
        "gates": {
            "G0": "NOT_RUN",
            "G1": "NOT_RUN",
            "G2": "NOT_RUN" if artifacts_verified else "BLOCKED_MODEL",
            "G3": "NOT_RUN" if inputs["dataset_manifest_sha256"] else "BLOCKED_DATA",
            "G4": "NOT_RUN" if inputs["dataset_manifest_sha256"] else "BLOCKED_DATA",
            "G5": "NOT_RUN",
        },
        "inputs": {**inputs, "encoder_fingerprint": encoder_fingerprint},
        "server_attestation": attestation,
        "environment": {
            "python": platform.python_version(),
            "platform": platform.platform(),
            "profile": args.profile,
            "server_profile": attestation.get("server_profile"),
            "gpu": None,
            "artifacts_verified": artifacts_verified,
        },
        "configuration": {
            "sessions": args.sessions,
            "route_id": str(args.route_id),
            "warmup_seconds": args.warmup_seconds,
            "duration_seconds": args.duration_seconds,
            "max_client_rate_hz": 5,
            "request_deadline_ms": 1000,
            "jpeg_quality": 75,
            "observed_frame_dimensions": sorted(dataset.dimensions),
            "route_checkpoint_counts": checkpoint_counts,
            "standard_route_workload_attested": standard_route,
            "request_window": "challenge received in [warmup,end); all resulting tails included",
            "percentile_method": "nearest_rank",
            "completed_measurement": completed,
            "instruction_presentation": "immediate simulated event with received/presented ACKs",
        },
        **summary,
        "resources": sampler.summary(),
        "performance": performance_decision(
            summary,
            sessions=args.sessions,
            warmup=args.warmup_seconds,
            duration=args.duration_seconds,
            completed=completed,
            attested=attested,
            real_models=real_models,
            standard_frames=dataset.dimensions == {(640, 480)},
            standard_route=standard_route,
        ),
        "navigation": {
            "false_turns": None,
            "missed_turns": None,
            "early_arrivals": None,
            "completed_positive_clips": None,
        },
        "limitations": [
            "Recorded pixels loop; this is not independent pilot evidence or live capture",
            "G4 requires separately source-bound G3, fault matrix and 500-session cleanup evidence",
            "Operator-local attestation is an operator claim, not cryptographic server identity",
            "Requested profile is not verified server hardware until server attestation matches",
            "HTTP health RTT includes HTTP processing and is a conservative network RTT proxy",
            "Presentation is immediate; physical audio/device latency was not measured",
            "Four sessions have no throughput guarantee; queue/concurrency need server evidence",
            "RSS/VRAM peaks are sampled, may miss short spikes, and are null when unavailable",
        ],
    }
    return report


def write_report(report: dict, directory: Path) -> Path:
    directory = directory.absolute()
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"benchmark-{report['run_id']}.json"
    descriptor, temporary = tempfile.mkstemp(prefix=".navcore-benchmark-", dir=directory)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(report, stream, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, target, follow_symlinks=False)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return target


def run_benchmark(args) -> int:
    try:
        report = asyncio.run(benchmark(args))
        path = write_report(report, args.report_dir)
    except (OSError, ValueError, TypeError):
        print(json.dumps({"error": "BENCHMARK_INPUT_OR_REPORT_INVALID"}))
        return 1
    print(json.dumps({"report": str(path), "performance": report["performance"]["status"]}))
    status = report["performance"]["status"]
    return 0 if status in {"PASS", "MEASURED_CAPACITY"} else (1 if status.startswith("FAIL") else 2)
