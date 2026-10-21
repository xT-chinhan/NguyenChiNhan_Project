"""Benchmark evidence must expose missing data, rejected tails and insecure inputs."""

import argparse
import importlib
import io
import json
import os
import subprocess

import pytest
from PIL import Image

from tests.unit._benchmark_fixtures import (
    AckDelayWire,
    AdmissionFailureHTTP,
    JPEGDataset,
    acceptance_decision,
    check_script_environment,
    result_payload,
    write_device,
)


def metrics_module():
    return importlib.import_module("navcore.cli._benchmark_metrics")


def inputs_module():
    return importlib.import_module("navcore.cli._benchmark_inputs")


def test_quantiles_use_nearest_rank_and_never_invent_samples():
    quantiles = metrics_module().quantiles
    assert quantiles([]) == {"count": 0, "p50": None, "p95": None, "p99": None}
    assert quantiles([1, 2, 3, 100]) == {"count": 4, "p50": 2, "p95": 100, "p99": 100}
    with pytest.raises(ValueError):
        quantiles([float("nan")])


def test_request_window_excludes_warmup_but_keeps_late_results_and_unresolved_tail():
    stats = metrics_module().Metrics(0, 30, 300, 1)
    warm = stats.request("a", 1, 29.999)
    stats.result(warm, 30.2, result_payload())
    measured = stats.request("a", 2, 30)
    stats.result(measured, 30.8, result_payload(event_loop_lag_ms=12))
    tail = stats.request("a", 3, 329.999)
    stats.result(tail, 330.4, result_payload(event_loop_lag_ms=8))
    stats.request("a", 4, 329.9999)
    assert stats.request("a", 5, 330) is None
    stats.finish_pending(331.2)
    report = stats.summary()
    assert report["counts"]["frames_requested"] == 3
    assert report["counts"]["frames_received"] == 2
    assert report["counts"]["frames_unresolved"] == 1
    assert report["rejection_fraction"] == pytest.approx(1 / 3)
    assert report["latency_ms"]["p95"] == pytest.approx(800)
    assert report["server_timing_ms"]["event_loop_lag_ms"]["p95"] == 12


def test_missing_watchdog_is_null_and_blocks_complete_timing_evidence():
    stats = metrics_module().Metrics(0, 0, 1, 1)
    request = stats.request("a", 1, 0)
    stats.result(request, 0.1, result_payload())
    summary = stats.summary()
    assert summary["server_timing_ms"]["event_loop_lag_ms"]["count"] == 0
    assert summary["server_timing_ms"]["event_loop_lag_ms"]["p95"] is None
    assert summary["timing_complete"] is False


def test_rejection_uses_every_challenge_as_denominator():
    stats = metrics_module().Metrics(0, 0, 1, 1)
    for seq in range(1, 5):
        req = stats.request("a", seq, seq / 10)
        if seq == 1:
            stats.result(req, 0.2, result_payload(event_loop_lag_ms=1))
        elif seq == 2:
            stats.reject(req, "FRAME_EXPIRED")
        elif seq == 3:
            stats.reject(req, "WORKER_BUSY")
    stats.finish_pending(2)
    summary = stats.summary()
    assert summary["rejection_fraction"] == 0.75
    assert summary["counts"]["frames_expired"] == 1
    assert summary["rejection_codes"] == {"FRAME_EXPIRED": 1, "WORKER_BUSY": 1}


def test_instructions_are_checked_again_after_ack_delay_and_at_both_ttl_bounds():
    guard = metrics_module().InstructionGuard()
    instruction = {
        "id": "11111111-1111-4111-8111-111111111111",
        "code": "TURN_LEFT",
        "capture_monotonic_ms": 1000,
        "valid_for_ms": 200,
        "frame_seq": 1,
    }
    assert guard.fresh(instruction, 1700, 1899) is True
    assert guard.fresh(instruction, 1700, 1900) is False
    instruction["valid_for_ms"] = 500
    assert guard.fresh(instruction, 1700, 1999) is True
    assert guard.fresh(instruction, 1700, 2000) is False
    instruction["valid_for_ms"] = float("nan")
    assert guard.fresh(instruction, 1700, 1800) is False


@pytest.mark.parametrize("mode", [0o644, 0o640, 0o400, 0o700])
def test_device_files_require_exact_private_mode(tmp_path, mode):
    write_device(tmp_path).chmod(mode)
    with pytest.raises(ValueError, match="0600"):
        inputs_module().load_devices(tmp_path, 1)


def test_devices_reject_symlinks_and_duplicate_tokens_without_leaking_them(tmp_path):
    first = write_device(tmp_path)
    linked = tmp_path / "two.env"
    linked.symlink_to(first)
    with pytest.raises(ValueError, match="symlink"):
        inputs_module().load_devices(tmp_path, 1)
    linked.unlink()
    for index in range(2, 5):
        write_device(tmp_path, f"{index}.env")
    with pytest.raises(ValueError) as failure:
        inputs_module().load_devices(tmp_path, 4)
    assert "navdev_" not in str(failure.value)
    assert "distinct" in str(failure.value)


def test_one_session_can_use_one_of_four_provisioned_devices(tmp_path):
    for index, char in enumerate("abcd"):
        write_device(tmp_path, f"{index}.env", "navdev_" + char * 43)
    devices = inputs_module().load_devices(tmp_path, 1)
    assert len(devices) == 1
    assert devices[0].api_url == "http://127.0.0.1:8095"


def test_device_count_and_api_url_are_checked_before_any_network_use(tmp_path):
    write_device(tmp_path)
    with pytest.raises(ValueError, match="four"):
        inputs_module().load_devices(tmp_path, 4)
    write_device(tmp_path, "two.env", "navdev_" + "b" * 43)
    with pytest.raises(ValueError, match="one or four"):
        inputs_module().load_devices(tmp_path, 1)
    with pytest.raises(ValueError):
        inputs_module().validate_api_url("https://user:secret@example.org/?token=secret")


def test_frame_paths_cannot_escape_dataset_even_through_symlinks(tmp_path):
    outside = tmp_path.parent / "outside.jpg"
    outside.write_bytes(b"not used")
    (tmp_path / "linked.jpg").symlink_to(outside)
    manifest = tmp_path / "frames.jsonl"
    for relative in ("../outside.jpg", "linked.jpg", str(outside)):
        manifest.write_text(
            json.dumps(
                {
                    "sample_index": 0,
                    "pts_ms": 0,
                    "relative_path": relative,
                    "pixel_sha256": "a" * 64,
                }
            )
            + "\n"
        )
        with pytest.raises(ValueError):
            inputs_module().FrameDataset.load(manifest)


def test_source_identity_includes_uncommitted_bytes_and_excludes_bytecode(tmp_path):
    source = tmp_path / "src" / "navcore"
    source.mkdir(parents=True)
    code = source / "app.py"
    code.write_text("one\n")
    identity = inputs_module().source_identity(tmp_path)
    (source / "app.pyc").write_bytes(b"cache")
    assert inputs_module().source_identity(tmp_path) == identity
    code.write_text("two\n")
    assert inputs_module().source_identity(tmp_path) != identity


def test_attestation_is_blocked_when_absent_or_different_source(tmp_path):
    module = inputs_module()
    inputs = {key: "a" * 64 for key in module.SERVER_INPUT_KEYS}
    assert (
        module.check_attestation(None, inputs, "http://127.0.0.1:8095", "cpu")["status"]
        == "BLOCKED_ATTESTATION"
    )
    receipt = tmp_path / "receipt.json"
    receipt.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "attestation_kind": "operator_local",
                "server_instance_id": "11111111-1111-4111-8111-111111111111",
                "api_url": "http://127.0.0.1:8095",
                "profile": "cpu",
                "adapter_kind": "real_models",
                "inputs": inputs,
            }
        )
    )
    assert (
        module.check_attestation(receipt, inputs, "http://127.0.0.1:8095", "cpu")["status"]
        == "MATCHED_OPERATOR_ATTESTATION"
    )
    inputs = {**inputs, "source_sha256": "b" * 64}
    assert (
        module.check_attestation(receipt, inputs, "http://127.0.0.1:8095", "cpu")["status"]
        == "BLOCKED_ATTESTATION"
    )


def test_cli_requires_route_frames_models_and_supports_separate_profiles():
    module = importlib.import_module("navcore.cli.benchmark")
    parser = argparse.ArgumentParser()
    module.register_benchmark(parser.add_subparsers(dest="command", required=True))
    args = parser.parse_args(
        [
            "benchmark",
            "--device-env-dir",
            "devices",
            "--sessions",
            "1",
            "--route-id",
            "11111111-1111-4111-8111-111111111111",
            "--frames-jsonl",
            "frames.jsonl",
            "--model-dir",
            "models",
            "--report-dir",
            "reports",
            "--profile",
            "cuda:0",
        ]
    )
    assert (args.warmup_seconds, args.duration_seconds, args.profile) == (30, 300, "cuda:0")
    with pytest.raises(SystemExit):
        parser.parse_args(["benchmark", "--device-env-dir", "devices", "--sessions", "1"])


def test_no_metric_report_cannot_claim_performance_or_g4_pass():
    module = metrics_module()
    stats = module.Metrics(0, 30, 300, 1)
    decision = acceptance_decision(stats.summary())
    assert decision["status"] == "BLOCKED_METRICS"
    assert decision["checks"]["server_p95_at_most_700ms"] is None


def test_short_run_and_unknown_resources_never_become_acceptance_pass():
    module = metrics_module()
    stats = module.Metrics(0, 0, 1, 1)
    req = stats.request("a", 1, 0)
    stats.result(req, 0.1, result_payload(event_loop_lag_ms=1))
    stats.rtt_ms.append(1)
    decision = acceptance_decision(stats.summary(), warmup=0, duration=1)
    assert decision["status"] == "BLOCKED_PROFILE"
    from navcore.cli._benchmark_transport import ResourceSampler

    assert ResourceSampler(None).summary()["rss_peak_bytes"] is None
    assert ResourceSampler(None).summary()["vram_peak_bytes"] is None


def test_current_process_rss_sampling_is_real_and_never_sentinel_zero():
    from navcore.cli._benchmark_transport import ResourceSampler

    sampler = ResourceSampler(os.getpid())
    sampler.sample_rss()
    assert sampler.summary()["rss_peak_bytes"] > 0


def test_high_measured_rtt_fails_one_session_target_even_with_fast_model():
    module = metrics_module()
    stats = module.Metrics(0, 30, 300, 1)
    req = stats.request("a", 1, 30)
    stats.result(req, 30.2, result_payload(event_loop_lag_ms=1))
    stats.rtt_ms.append(101)
    decision = acceptance_decision(stats.summary())
    assert decision["status"] == "FAIL_PERFORMANCE"
    assert decision["checks"]["http_health_rtt_p95_at_most_100ms"] is False


def test_nonstandard_route_cannot_claim_profile_acceptance():
    module = metrics_module()
    stats = module.Metrics(0, 30, 300, 1)
    req = stats.request("a", 1, 30)
    stats.result(req, 30.2, result_payload(event_loop_lag_ms=1))
    stats.rtt_ms.append(1)
    decision = acceptance_decision(stats.summary(), standard_route=False)
    assert decision["status"] == "BLOCKED_PROFILE"


def test_missing_process_rss_is_unknown_instead_of_zero():
    from navcore.cli._benchmark_transport import ResourceSampler

    sampler = ResourceSampler(2**30)
    sampler.sample_rss()
    assert sampler.summary()["rss_peak_bytes"] is None
    assert sampler.summary()["rss_read_failures"] > 0


def test_check_script_refuses_dev_database_and_models_are_explicit(tmp_path):
    script, log, environment = check_script_environment(tmp_path)
    environment["NAV_TEST_DB_URL"] = "postgresql://localhost/navcore"
    denied = subprocess.run(
        ["bash", str(script)], env=environment, capture_output=True, check=False
    )
    assert denied.returncode == 2
    assert not log.exists()
    environment["NAV_TEST_DB_URL"] = "postgresql://localhost/navcore_test"
    allowed = subprocess.run(
        ["bash", str(script)], env=environment, capture_output=True, check=False
    )
    assert allowed.returncode == 0, allowed.stderr
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    assert ["-m", "ruff", "format", "--check", "src", "tests"] in calls
    assert ["-m", "ruff", "check", "src", "tests"] in calls
    assert ["-m", "pytest", "tests/integration", "-q"] in calls
    assert not any("tests/model" in call for call in calls)
    log.unlink()
    allowed = subprocess.run(
        ["bash", str(script), "--model"],
        env=environment,
        capture_output=True,
        check=False,
    )
    assert allowed.returncode == 0
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    assert ["-m", "pytest", "tests/model", "-m", "model", "-q"] in calls


def test_prepared_frame_decode_enforces_pixels_and_sends_quality75_jpeg(tmp_path):
    from navcore.vision.images import decode_image

    data = io.BytesIO()
    Image.new("RGB", (640, 480), (10, 20, 30)).save(data, format="JPEG", quality=95)
    frame = tmp_path / "frame.jpg"
    frame.write_bytes(data.getvalue())
    manifest = tmp_path / "frames.jsonl"
    manifest.write_text(
        json.dumps(
            {
                "sample_index": 0,
                "pts_ms": 0,
                "relative_path": "frame.jpg",
                "pixel_sha256": decode_image(data.getvalue()).pixel_sha256,
            }
        )
        + "\n"
    )
    dataset = inputs_module().FrameDataset.load(manifest)
    encoded = dataset.jpeg(1000)
    assert decode_image(encoded).rgb.shape == (480, 640, 3)
    assert dataset.dimensions == {(640, 480)}
    Image.new("RGB", (640, 480), (200, 0, 0)).save(frame, format="JPEG")
    with pytest.raises(ValueError, match="integrity"):
        dataset.jpeg(2000)


@pytest.mark.asyncio
async def test_network_driver_echoes_challenge_and_drops_expired_instruction_after_ack():
    from navcore.cli._benchmark_transport import drive_stream

    now = [30.0]
    stats = metrics_module().Metrics(0, 30, 0.5, 1)
    session_id = "11111111-1111-4111-8111-111111111111"
    token = "22222222-2222-4222-8222-222222222222"
    wire = AckDelayWire(now, session_id, token)
    assert await drive_stream(wire, session_id, JPEGDataset(), stats, clock=lambda: now[0])
    assert stats.summary()["counts"]["frames_received"] == 1
    assert stats.summary()["counts"]["instructions_dropped"] == 1
    assert stats.summary()["counts"]["stale_instructions_presented"] == 0
    assert not any(message.get("stage") == "presented" for message in wire.sent)


@pytest.mark.asyncio
async def test_setup_failure_cleans_created_sessions_and_preserves_blocked_gates(
    tmp_path, monkeypatch
):
    module = importlib.import_module("navcore.cli.benchmark")
    devices = tmp_path / "devices"
    devices.mkdir()
    for index, char in enumerate("abcd"):
        write_device(devices, f"{index}.env", "navdev_" + char * 43)
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "source.py").write_text("source\n")
    (tmp_path / "frame.jpg").write_bytes(b"not decoded before setup failure")
    frames = tmp_path / "frames.jsonl"
    frames.write_text(
        json.dumps(
            {
                "sample_index": 0,
                "pts_ms": 0,
                "relative_path": "frame.jpg",
                "pixel_sha256": "a" * 64,
            }
        )
        + "\n"
    )
    created = "11111111-1111-4111-8111-111111111111"
    http = AdmissionFailureHTTP(created)
    monkeypatch.setattr(module.httpx, "AsyncClient", lambda **kwargs: http)
    args = argparse.Namespace(
        device_env_dir=devices,
        sessions=4,
        route_id=created,
        frames_jsonl=frames,
        model_dir=tmp_path / "missing-models",
        warmup_seconds=30,
        duration_seconds=300,
        source_root=tmp_path,
        dataset_manifest=None,
        server_receipt=None,
        backend_pid=None,
        profile="cpu",
    )
    report = await module.benchmark(args)
    assert http.deleted == [f"/v1/sessions/{created}"]
    assert report["performance"]["status"] == "BLOCKED_ATTESTATION"
    assert report["gates"]["G4"] == "BLOCKED_DATA"
    assert report["resources"]["rss_peak_bytes"] is None
    assert report["environment"]["server_profile"] is None
    assert report["counts"]["frames_requested"] == 0


def test_report_write_is_private_atomic_and_never_overwrites(tmp_path):
    module = importlib.import_module("navcore.cli.benchmark")
    identity = "11111111-1111-4111-8111-111111111111"
    with pytest.raises(ValueError):
        module.write_report({"run_id": identity, "invalid": float("nan")}, tmp_path)
    assert list(tmp_path.iterdir()) == []
    report = {"run_id": identity, "latency_ms": None}
    path = module.write_report(report, tmp_path)
    assert path.stat().st_mode & 0o777 == 0o600
    with pytest.raises(FileExistsError):
        module.write_report({**report, "latency_ms": 999}, tmp_path)
    assert json.loads(path.read_text()) == report


@pytest.mark.asyncio
async def test_websocket_debug_logging_cannot_expose_credentials_or_frames(monkeypatch, caplog):
    import asyncio
    import logging

    from navcore.cli import _benchmark_transport as transport

    token = "navdev_" + "z" * 43
    caplog.set_level(logging.DEBUG)

    class Connection:
        def __init__(self, *args, **kwargs):
            kwargs["logger"].debug("Authorization: Bearer %s raw_frame=private", token)

        async def __aenter__(self):
            return None

        async def __aexit__(self, *args):
            pass

    monkeypatch.setattr(transport, "connect", Connection)
    device = inputs_module().Device("http://127.0.0.1:8095", token)
    await transport.run_stream(
        {"id": "11111111-1111-4111-8111-111111111111"},
        device,
        None,
        metrics_module().Metrics(0, 0, 0, 1),
        asyncio.Barrier(1),
        asyncio.Event(),
    )
    assert token not in caplog.text
    assert "raw_frame=private" not in caplog.text
