"""Fail-closed pilot evaluator with consistent machine/human evidence reports."""

import argparse
import json
import math
import platform
from pathlib import Path
from uuid import uuid4

from navcore.cli.bundle import file_sha256, load_bundle, read_json
from navcore.cli.dataset import validate_dataset
from navcore.cli.evidence import local_inputs
from navcore.cli.metrics import (
    navigation_metrics,
    percentile,
    perception_metrics,
    valid_presentation,
)
from navcore.cli.trace_validation import coverage_missing, validate_trace


def load_trace(path: Path) -> list[dict]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("Missing or oversized trace")
    events = []
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if len(line) > 65536 or len(events) >= 200000:
                raise ValueError("Oversized trace record")
            event = json.loads(
                line,
                parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite trace")),
            )
            if not isinstance(event, dict) or any(
                key in event for key in ("image_b64", "png_b64", "token", "authorization")
            ):
                raise ValueError("Invalid or secret-bearing trace")
            events.append(event)
    if not events or events[0].get("type") != "run_start" or events[0].get("schema_version") != 1:
        raise ValueError("Trace run header missing")
    if sum(e.get("type") == "run_start" for e in events) != 1:
        raise ValueError("Multiple trace run headers")
    return events


def _base_report() -> dict:
    return {
        "schema_version": 1,
        "run_id": str(uuid4()),
        "evidence_kind": "network_replay",
        "adapter_kind": "unverified_server",
        "gates": {
            "G0": "NOT_RUN",
            "G1": "NOT_RUN",
            "G2": "BLOCKED_MODEL",
            "G3": "BLOCKED_DATA",
            "G4": "BLOCKED_DATA",
            "G5": "NOT_RUN",
        },
        "inputs": {**local_inputs(), "dataset_manifest_sha256": None},
        "environment": {
            "python": platform.python_version(),
            "profile": "unverified",
            "gpu": None,
        },
        "counts": {
            "frames_requested": 0,
            "frames_received": 0,
            "frames_expired": 0,
            "stale_instructions_presented": 0,
            "stale_proposals_dropped": 0,
        },
        "navigation": {
            "false_turns": None,
            "missed_turns": None,
            "early_arrivals": None,
            "out_of_route_progress": None,
            "completed_positive_clips": None,
        },
        "latency_ms": {"p50": None, "p95": None, "p99": None},
        "perception": {
            "precision": None,
            "recall": None,
            "object_frames_observed": None,
            "clear_frames_observed": None,
        },
        "clips": {},
        "limitations": [],
    }


def render_markdown(report: dict) -> str:
    lines = [
        "# Pilot evaluation",
        "",
        f"Run: {report['run_id']}",
        "",
        f"Evidence: {report['evidence_kind']}; adapter: {report['adapter_kind']}",
        "",
        "| Gate | Result |",
        "|---|---|",
    ]
    lines += [f"| {key} | {value} |" for key, value in report["gates"].items()]
    for section in ("counts", "navigation", "perception", "latency_ms", "inputs"):
        lines += ["", f"## {section}", "", "| Metric | Value |", "|---|---|"]
        lines += [
            f"| {key} | {json.dumps(value, ensure_ascii=False)} |"
            for key, value in report[section].items()
        ]
    lines += ["", "## Limitations", ""] + ["- " + item for item in report["limitations"]]
    return "\n".join(lines) + "\n"


def write_reports(report: dict, output: Path) -> None:
    encoded = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)
    if json.loads(encoded) != report:
        raise ValueError("Report serialization mismatch")
    markdown = render_markdown(report)
    for gate, value in report["gates"].items():
        if f"| {gate} | {value} |" not in markdown:
            raise ValueError("Markdown gate mismatch")
    output.mkdir(parents=True, exist_ok=True)
    for name in ("report.json", "report.md"):
        if (output / name).exists():
            raise ValueError("Report already exists; choose a new report directory")
    with (output / "report.json").open("x", encoding="utf-8") as stream:
        stream.write(encoded + "\n")
    with (output / "report.md").open("x", encoding="utf-8") as stream:
        stream.write(markdown)


def _server_receipt(path: Path | None, traces: list[Path], report: dict) -> bool:
    if path is None:
        report["limitations"].append(
            "Server model/source identity is unverified; no local attestation supplied"
        )
        return False
    receipt = read_json(path)
    inputs = receipt.get("inputs", {})
    hashes = (
        "source_sha256",
        "uv_lock_sha256",
        "model_manifest_sha256",
        "policy_sha256",
    )
    for key in hashes:
        value = inputs.get(key)
        if (
            not isinstance(value, str)
            or len(value) != 64
            or any(c not in "0123456789abcdef" for c in value)
        ):
            raise ValueError("Invalid server receipt input hash")
    expected = sorted(file_sha256(trace) for trace in traces)
    attestation = receipt.get("attestation", {})
    if (
        receipt.get("schema_version") != 1
        or receipt.get("adapter_kind") != "real_models"
        or attestation.get("kind") != "local_run"
        or attestation.get("trace_sha256") != expected
        or attestation.get("model_smoke_verified") is not True
    ):
        raise ValueError("Server receipt does not attest these traces and real model smoke")
    report["inputs"]["server_inputs"] = inputs
    report["inputs"]["server_receipt_sha256"] = file_sha256(path)
    report["adapter_kind"] = "real_models_local_attestation"
    report["gates"]["G2"] = "PASS_ATTESTED"
    report["environment"]["profile"] = receipt.get("environment", {}).get("profile", "unverified")
    report["limitations"].append(
        "Server identity is supported by a local operator attestation, not remote authentication"
    )
    return True


def evaluate(args: argparse.Namespace) -> int:
    report = _base_report()
    root = args.ground_truth.absolute().parent
    manifest_path = args.dataset_manifest or root / "dataset-manifest.json"
    bundle_path = args.bundle or root / "bundle.json"
    required = [args.ground_truth, manifest_path, bundle_path]
    missing = ["Missing pilot input: " + path.name for path in required if not path.is_file()]
    if not args.trace:
        missing.append("No network replay traces supplied")
    if missing:
        report["limitations"] += missing
        write_reports(report, args.report_dir)
        return 2
    bundle = load_bundle(bundle_path)
    if bundle.path.parent.resolve() != root.resolve():
        raise ValueError("Bundle and annotations must share their root")
    manifest, truth, missing = validate_dataset(root, manifest_path, args.ground_truth, bundle)
    report["inputs"].update(
        dataset_manifest_sha256=file_sha256(manifest_path),
        ground_truth_sha256=file_sha256(args.ground_truth),
        bundle_sha256=file_sha256(bundle_path),
        trace_sha256=[file_sha256(path) for path in args.trace],
    )
    traces = {}
    for path in args.trace:
        events = validate_trace(load_trace(path))
        header = events[0]
        clip_id = header.get("clip_id")
        if clip_id in traces or clip_id not in {c.clip_id for c in truth.clips}:
            raise ValueError("Duplicate or unknown trace clip")
        if header.get("evidence_kind") != "network_replay":
            raise ValueError("Pilot requires network replay evidence")
        if not any(e.get("type") == "run_end" for e in events):
            missing.append("Incomplete trace: " + clip_id)
        clip = next(c for c in truth.clips if c.clip_id == clip_id)
        row = next(row for row in manifest.files if row.path == clip.file)
        if not clip.expected_completion and coverage_missing(events, row.duration_ms):
            missing.append("Incomplete negative replay coverage: " + clip_id)
        if header.get("query_source_sha256") != row.sha256:
            raise ValueError("Trace query hash does not match dataset")
        for event in events:
            if (
                event.get("type") == "frame_sent"
                and event.get("pixel_sha256") not in row.pixel_sha256
            ):
                raise ValueError("Trace canonical pixels do not match dataset")
        traces[clip_id] = events
    required_clips = {c.clip_id for c in truth.clips if c.split == "test"}
    missing += [
        "Missing test replay trace: " + clip for clip in sorted(required_clips - traces.keys())
    ]
    attested = _server_receipt(args.server_receipt, args.trace, report)
    all_events = [
        event for clip_id, events in traces.items() if clip_id in required_clips for event in events
    ]
    report["counts"] = {
        "frames_requested": sum(e.get("type") == "capture_request" for e in all_events),
        "frames_received": sum(e.get("type") == "frame_result" for e in all_events),
        "frames_expired": sum(
            e.get("type") == "frame_rejected" and e.get("code") == "FRAME_EXPIRED"
            for e in all_events
        ),
        "stale_instructions_presented": sum(
            e.get("type") == "instruction_presented" and not valid_presentation(e)
            for e in all_events
        ),
        "stale_proposals_dropped": sum(
            e.get("type") == "instruction_dropped" and "EXPIRED" in e.get("reason", "")
            for e in all_events
        ),
    }
    latency = [
        e["request_to_receive_ms"]
        for e in all_events
        if e.get("type") == "frame_result"
        and type(e.get("request_to_receive_ms")) in {float, int}
        and math.isfinite(e["request_to_receive_ms"])
        and e["request_to_receive_ms"] >= 0
    ]
    report["latency_ms"] = {
        name: percentile(latency, q) for name, q in (("p50", 0.5), ("p95", 0.95), ("p99", 0.99))
    }
    nav = {
        key: 0
        for key in (
            "false_turns",
            "early_turns",
            "missed_turns",
            "early_arrivals",
            "out_of_route_progress",
            "forbidden_instructions",
            "skipped_checkpoints",
            "wrong_window_progress",
            "completed_positive_clips",
        )
    }
    perception = {
        key: 0
        for key in (
            "true_positives",
            "false_positives",
            "false_negatives",
            "labelled_frames_observed",
            "labelled_frames_missing",
            "object_frames_observed",
            "clear_frames_observed",
        )
    }
    orientation = []
    for clip in truth.clips:
        if clip.split != "test" or clip.clip_id not in traces:
            continue
        events = traces[clip.clip_id]
        metrics = navigation_metrics(clip, events)
        report["clips"][clip.clip_id] = metrics
        for key in nav:
            nav[key] += (
                int(metrics["completed"]) if key == "completed_positive_clips" else metrics[key]
            )
        for key, value in perception_metrics(clip, events).items():
            perception[key] += value
        orientation += [
            e.get("localization", {}).get("orientation_verified") is True
            for e in events
            if e.get("type") == "frame_result" and e.get("accepted_fresh")
        ]
    if traces.keys() & required_clips:
        report["navigation"] = nav
        report["orientation_verified_fraction"] = (
            sum(orientation) / len(orientation) if orientation else None
        )
        tp, fp, fn = (
            perception[key] for key in ("true_positives", "false_positives", "false_negatives")
        )
        report["perception"] = {
            **perception,
            "precision": tp / (tp + fp) if tp + fp else None,
            "recall": tp / (tp + fn) if tp + fn else None,
        }
        if perception["object_frames_observed"] < 30 or perception["clear_frames_observed"] < 30:
            missing.append("Replay lacks thirty observed labelled object and thirty clear frames")
        if perception["labelled_frames_missing"]:
            missing.append("Some independently labelled perception frames were not observed")
    report["limitations"] += missing
    if missing:
        write_reports(report, args.report_dir)
        return 2
    positive_count = sum(c.split == "test" and c.expected_completion for c in truth.clips)
    report["gates"]["G4"] = "NOT_RUN"
    bad_nav = (
        any(nav[key] for key in nav if key != "completed_positive_clips")
        or nav["completed_positive_clips"] != positive_count
    )
    bad_perception = (
        report["perception"]["precision"] is None
        or report["perception"]["precision"] < 0.8
        or report["perception"]["recall"] is None
        or report["perception"]["recall"] < 0.8
    )
    stale = report["counts"]["stale_instructions_presented"] > 0
    report["gates"]["G3"] = (
        "FAIL_PERCEPTION"
        if bad_perception
        else "FAIL"
        if bad_nav or stale
        else "PASS"
        if attested
        else "BLOCKED_MODEL"
    )
    write_reports(report, args.report_dir)
    return 1 if bad_nav or bad_perception or stale else 0 if attested else 2
