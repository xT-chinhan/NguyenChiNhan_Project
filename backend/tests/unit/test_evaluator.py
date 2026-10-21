import argparse
import hashlib
import json
from pathlib import Path

import pytest

from navcore.cli.bundle import file_sha256, load_bundle
from navcore.cli.dataset import ClipLabel, validate_dataset
from navcore.cli.evaluate import evaluate, render_markdown
from navcore.cli.metrics import (
    navigation_metrics,
    perception_metrics,
    valid_presentation,
)
from tests.unit.test_route_bundle import make_bundle


def dataset(root: Path):
    bundle_path = make_bundle(root)
    bundle = load_bundle(bundle_path)
    files = []
    for checkpoint, paths, pixels in zip(
        bundle.data.checkpoints, bundle.images, bundle.pixel_hashes, strict=True
    ):
        for path, pixel in zip(paths, pixels, strict=True):
            files.append(
                {
                    "path": path.relative_to(root).as_posix(),
                    "sha256": file_sha256(path),
                    "source": "reference",
                    "split": "reference",
                    "capture_group": checkpoint.source_group,
                    "pixel_sha256": [pixel],
                }
            )
    clips = []
    for index, (clip_id, split, positive) in enumerate(
        [
            ("dev", "dev", True),
            ("positive-1", "test", True),
            ("positive-2", "test", True),
            ("wrong-corridor", "test", False),
            ("reverse-direction", "test", False),
        ]
    ):
        relative = "queries/" + clip_id + ".mp4"
        path = root / relative
        path.parent.mkdir(exist_ok=True)
        # Schema/split unit fixtures are not footage and never provide real AI evidence.
        path.write_bytes(("synthetic-schema-only-" + clip_id).encode())
        pixel = hashlib.sha256(clip_id.encode()).hexdigest()
        files.append(
            {
                "path": relative,
                "sha256": file_sha256(path),
                "source": "query",
                "split": split,
                "capture_group": "query-" + clip_id,
                "pixel_sha256": [pixel],
            }
        )
        checkpoints = (
            [
                {
                    "seq": seq,
                    "visible_start_ms": seq * 1000,
                    "visible_end_ms": seq * 1000 + 800,
                    "expected_code": code,
                }
                for seq, code in enumerate(
                    ["CONTINUE_STRAIGHT", "TURN_LEFT", "TURN_RIGHT", "ARRIVED"]
                )
            ]
            if positive
            else []
        )
        perception = []
        if clip_id == "positive-1":
            perception = [
                {
                    "pts_ms": i * 200,
                    "objects": [
                        {
                            "class_name": "person",
                            "bbox": [0, 0, 100, 100],
                            "rgb_notice_expected": True,
                        }
                    ]
                    if i < 30
                    else [],
                }
                for i in range(60)
            ]
        clips.append(
            {
                "clip_id": clip_id,
                "file": relative,
                "split": split,
                "capture_group": "query-" + clip_id,
                "expected_completion": positive,
                "checkpoints": checkpoints,
                "objects": [],
                "perception_frames": perception,
                "forbidden_intervals": [],
            }
        )
    manifest = {
        "schema_version": 1,
        "dataset_id": "schema-unit-fixture",
        "created_at": "2026-10-21T00:00:00Z",
        "files": files,
    }
    truth = {
        "schema_version": 1,
        "annotation_provenance": {"kind": "human", "independent_of_model": True},
        "clips": clips,
    }
    manifest_path, truth_path = (
        root / "dataset-manifest.json",
        root / "ground_truth.json",
    )
    manifest_path.write_text(json.dumps(manifest))
    truth_path.write_text(json.dumps(truth))
    return bundle_path, manifest_path, truth_path, manifest, truth


def presentation(code, pts, seq=1, now=200, capture=100):
    return {
        "type": "instruction_presented",
        "code": code,
        "video_pts_ms": pts,
        "frame_seq": seq,
        "capture_monotonic_ms": capture,
        "received_monotonic_ms": 150,
        "presented_monotonic_ms": now,
        "valid_until_monotonic_ms": 500,
    }


def test_independent_turn_windows_stale_delivery_and_negative_progress():
    clip = ClipLabel.model_validate(
        {
            "clip_id": "positive",
            "file": "queries/a.mp4",
            "split": "test",
            "capture_group": "q",
            "expected_completion": True,
            "checkpoints": [
                {
                    "seq": 1,
                    "visible_start_ms": 6000,
                    "visible_end_ms": 8500,
                    "expected_code": "TURN_LEFT",
                }
            ],
        }
    )
    events = [
        {
            "type": "frame_result",
            "seq": 1,
            "last_confirmed_seq": 1,
            "accepted_fresh": True,
            "video_pts_ms": 7000,
        },
        presentation("TURN_LEFT", 5000),
    ]
    result = navigation_metrics(clip, events)
    assert result["false_turns"] == 1 and result["early_turns"] == 1 and result["missed_turns"] == 1
    events[1] = presentation("TURN_LEFT", 7000)
    assert navigation_metrics(clip, events)["missed_turns"] == 0
    assert not valid_presentation(presentation("TURN_LEFT", 7000, now=1100))
    negative = clip.model_copy(update={"expected_completion": False, "checkpoints": []})
    assert navigation_metrics(negative, events)["out_of_route_progress"] == 1


def test_perception_iou_and_matching_are_independent_and_one_to_one():
    clip = ClipLabel.model_validate(
        {
            "clip_id": "p",
            "file": "q.mp4",
            "split": "test",
            "capture_group": "q",
            "expected_completion": False,
            "checkpoints": [],
            "perception_frames": [
                {
                    "pts_ms": 0,
                    "objects": [
                        {
                            "class_name": "person",
                            "bbox": [0, 0, 100, 100],
                            "rgb_notice_expected": True,
                        },
                        {
                            "class_name": "chair",
                            "bbox": [200, 0, 300, 100],
                            "rgb_notice_expected": False,
                        },
                    ],
                },
                {"pts_ms": 200, "objects": []},
            ],
        }
    )
    frame = {
        "type": "frame_result",
        "video_pts_ms": 0,
        "accepted_fresh": True,
        "obstacles": [
            {"class_name": "person", "bbox": [0, 0, 100, 100], "confidence": 0.9},
            {"class_name": "person", "bbox": [0, 0, 100, 100], "confidence": 0.9},
        ],
    }
    result = perception_metrics(clip, [frame])
    assert (
        result["true_positives"],
        result["false_positives"],
        result["false_negatives"],
    ) == (1, 1, 1)
    assert result["labelled_frames_missing"] == 1
    clear = {
        "type": "frame_result",
        "video_pts_ms": 200,
        "accepted_fresh": True,
        "obstacles": [{"class_name": "chair", "bbox": [0, 0, 100, 100], "confidence": 0.8}],
    }
    result = perception_metrics(clip, [frame, clear])
    assert result["false_positives"] == 2
    assert result["clear_frames_observed"] == 1
    assert result["labelled_frames_missing"] == 0


@pytest.mark.parametrize("leakage", ["group", "file", "pixel"])
def test_split_hash_and_group_leakage_rejected(tmp_path, leakage):
    bundle_path, manifest_path, truth_path, manifest, _truth = dataset(tmp_path)
    ref, query = manifest["files"][0], manifest["files"][12]
    if leakage == "group":
        query["capture_group"] = ref["capture_group"]
    elif leakage == "pixel":
        query["pixel_sha256"] = ref["pixel_sha256"]
    else:
        (tmp_path / query["path"]).write_bytes((tmp_path / ref["path"]).read_bytes())
        query["sha256"] = ref["sha256"]
    manifest_path.write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match="leakage"):
        validate_dataset(tmp_path, manifest_path, truth_path, load_bundle(bundle_path))


def test_missing_pilot_returns_exit_two_with_null_unmeasured_metrics(tmp_path):
    args = argparse.Namespace(
        ground_truth=tmp_path / "missing.json",
        dataset_manifest=None,
        bundle=None,
        trace=[],
        report_dir=tmp_path / "report",
        server_receipt=None,
    )
    assert evaluate(args) == 2
    report = json.loads((args.report_dir / "report.json").read_text())
    assert report["gates"]["G3"] == "BLOCKED_DATA"
    assert report["navigation"]["false_turns"] is None
    assert (args.report_dir / "report.md").read_text() == render_markdown(report)


def test_one_trace_cannot_claim_full_g3_or_real_models(tmp_path):
    bundle, manifest_path, truth_path, manifest, _truth = dataset(tmp_path)
    query = manifest["files"][13]
    trace = tmp_path / "trace.jsonl"
    trace.write_text(
        json.dumps(
            {
                "type": "run_start",
                "schema_version": 1,
                "clip_id": "positive-1",
                "evidence_kind": "network_replay",
                "query_source_sha256": query["sha256"],
            }
        )
        + "\n"
        + json.dumps({"type": "run_end"})
        + "\n"
    )
    args = argparse.Namespace(
        ground_truth=truth_path,
        dataset_manifest=manifest_path,
        bundle=bundle,
        trace=[trace],
        report_dir=tmp_path / "report",
        server_receipt=None,
    )
    assert evaluate(args) == 2
    report = json.loads((args.report_dir / "report.json").read_text())
    assert report["gates"]["G3"] == "BLOCKED_DATA"
    assert report["adapter_kind"] == "unverified_server"
    assert any("Missing test replay trace" in line for line in report["limitations"])
    assert report["perception"]["precision"] is None
