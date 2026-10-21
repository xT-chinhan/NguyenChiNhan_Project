import argparse
import copy
import hashlib
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import httpx
import numpy as np

from navcore.vision.artifacts import (
    COCO_LABELS,
    DINO_REPOSITORY,
    DINO_REVISION,
    DINO_URL,
    EXPORT_OPTIONS,
    PREPROCESS_VERSION,
    YOLO_BYTES,
    YOLO_SHA256,
    YOLO_URL,
    ArtifactError,
    encoder_fingerprint,
    safe_path,
    verify_artifacts,
)
from navcore.vision.detector import (
    DetectorError,
    Letterbox,
    letterbox_resize,
    yolo_postprocess,
)
from navcore.vision.pipeline import VisionPipeline


class DetectorPostprocessTest(unittest.TestCase):
    def setUp(self):
        self.transform = Letterbox(1, 0, 0, 224, 224)

    def predictions(self, rows):
        output = np.zeros((1, 300, 6), np.float32)
        output[0, : len(rows)] = rows
        return output

    def test_letterbox_rgb_scale_pad_and_input_contract(self):
        rgb = np.zeros((100, 200, 3), np.uint8)
        rgb[:] = (255, 0, 128)
        tensor, transform = letterbox_resize(rgb)
        self.assertEqual(transform, Letterbox(1.12, 0, 56, 200, 100))
        self.assertEqual(tensor.shape, (1, 3, 224, 224))
        self.assertEqual(tensor.dtype, np.float32)
        self.assertTrue(tensor.flags.c_contiguous)
        np.testing.assert_allclose(tensor[0, :, 0, 0], 114 / 255)
        np.testing.assert_allclose(tensor[0, :, 56, 0], [1, 0, 128 / 255])
        _, odd = letterbox_resize(np.zeros((101, 199, 3), np.uint8))
        self.assertEqual(odd.top, (224 - int(101 * odd.scale)) // 2)

    def test_coordinate_mapping_clamp_threshold_and_class80(self):
        transform = Letterbox(0.5, 0, 50, 400, 200)
        output = self.predictions([[-5, 45, 250, 170, 0.38, 79], [0, 50, 5, 55, 1, 0]])
        detections = yolo_postprocess(output, transform, COCO_LABELS)
        self.assertEqual(len(detections), 2)
        self.assertEqual(detections[0].bbox, (0, 0, 399, 199))
        self.assertEqual(detections[0].class_name, "toothbrush")
        self.assertEqual(detections[1].bbox, (0, 0, 10, 10))

    def test_invalid_rows_filtered_and_no_second_nms(self):
        rows = [
            [0, 0, 30, 30, 0.37, 0],
            [0, 0, 30, 30, 1.01, 0],
            [0, 0, 30, 30, 0.8, -1],
            [0, 0, 30, 30, 0.8, 80],
            [0, 0, 30, 30, 0.8, 0.5],
            [0, 0, 30, 30, np.nan, 0],
            [0, 0, np.inf, 30, 0.8, 0],
            [30, 0, 20, 30, 0.8, 0],
            [0, 0, 9.9, 30, 0.8, 0],
            [300, 0, 400, 30, 0.8, 0],
            [0, 0, 30, 30, 0.8, 0],
            [0, 0, 30, 30, 0.9, 0],
        ]
        detections = yolo_postprocess(self.predictions(rows), self.transform, COCO_LABELS)
        self.assertEqual(len(detections), 2)

    def test_contract_errors_raise_instead_of_guessing_shape(self):
        for output in (
            None,
            np.zeros((300, 6), np.float32),
            np.zeros((1, 84, 1029), np.float32),
            np.zeros((1, 300, 6), np.float64),
        ):
            with self.assertRaises(DetectorError):
                yolo_postprocess(output, self.transform, COCO_LABELS)

    def test_pipeline_failure_has_no_partial_result(self):
        class TestEncoder:
            fingerprint = "test-only"

            def encode(self, rgb):
                return np.ones(768, np.float32) / np.sqrt(np.float32(768))

        class FailedDetector:
            def detect(self, rgb):
                raise DetectorError("test branch failure")

        pipeline = VisionPipeline(TestEncoder(), FailedDetector())
        with self.assertRaises(DetectorError):
            pipeline.infer(np.zeros((32, 32, 3), np.uint8))


class ArtifactVerificationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        files = {}
        for name, content in {
            "config.json": b'{"model_type":"dinov2","hidden_size":768}',
            "preprocessor_config.json": b"{}",
            "model.safetensors": b"test-only-weight-data",
        }.items():
            path = safe_path(self.root, f"dinov2/{name}")
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(content)
            files[name] = {
                "sha256": hashlib.sha256(content).hexdigest(),
                "bytes": len(content),
                "url": f"{DINO_URL}/{name}",
            }
        content = b"test-only-onnx"
        path = safe_path(self.root, "yolo/yolo26n.onnx")
        path.parent.mkdir()
        path.write_bytes(content)
        self.manifest = {
            "version": 1,
            "encoder": {
                "repository": DINO_REPOSITORY,
                "revision": DINO_REVISION,
                "preprocess_version": PREPROCESS_VERSION,
                "license": "Apache-2.0",
                "files": files,
            },
            "detector": {
                "path": "yolo/yolo26n.onnx",
                "sha256": hashlib.sha256(content).hexdigest(),
                "bytes": len(content),
                "source_url": YOLO_URL,
                "source_sha256": YOLO_SHA256,
                "source_bytes": YOLO_BYTES,
                "input": [1, 3, 224, 224],
                "output": [1, 300, 6],
                "dtype": "float32",
                "labels": list(COCO_LABELS),
                "license": "AGPL-3.0-or-Enterprise",
                "export": {
                    "options": EXPORT_OPTIONS,
                    "parity": {"passed": True, "matched_rows": 300, "cutoff_tied_rows": 0},
                    "versions": {"ultralytics": "8.4.183", "onnx": "1.23.2"},
                },
            },
        }
        self.write_manifest()

    def write_manifest(self):
        (self.root / "manifest.json").write_text(json.dumps(self.manifest))

    def test_pins_integrity_and_encoder_only_fingerprint(self):
        artifacts = verify_artifacts(self.root)
        self.assertEqual(artifacts.labels, COCO_LABELS)
        changed = copy.deepcopy(self.manifest)
        changed["detector"]["sha256"] = "a" * 64
        self.assertEqual(encoder_fingerprint(changed["encoder"]), artifacts.encoder_fingerprint)
        (self.root / "dinov2/model.safetensors").write_bytes(b"changed-weight-data")
        with self.assertRaises(ArtifactError):
            verify_artifacts(self.root)

    def test_reject_traversal_absolute_and_symlink_paths(self):
        for relative in (
            "../secret",
            "/etc/passwd",
            "x/../secret",
            "x//secret",
            "./a",
            "x\\secret",
            "",
            "a/",
            "a\x00b",
        ):
            with self.subTest(relative=relative), self.assertRaises(ArtifactError):
                safe_path(self.root, relative)
        (self.root / "link").symlink_to(self.root / "dinov2", target_is_directory=True)
        with self.assertRaises(ArtifactError):
            safe_path(self.root, "link/config.json")
        (self.root / "yolo/yolo26n.onnx").unlink()
        (self.root / "yolo/yolo26n.onnx").symlink_to(self.root / "dinov2/model.safetensors")
        with self.assertRaises(ArtifactError):
            verify_artifacts(self.root)

    def test_manifest_source_shape_labels_and_missing_fields_fail(self):
        original = copy.deepcopy(self.manifest)
        for field, value in (
            ("path", "../model.onnx"),
            ("output", [1, 84, 1029]),
            ("labels", ["person"]),
            ("source_sha256", "0" * 64),
        ):
            self.manifest = copy.deepcopy(original)
            self.manifest["detector"][field] = value
            self.write_manifest()
            with self.assertRaises(ArtifactError):
                verify_artifacts(self.root)
        self.manifest = {"version": 1}
        self.write_manifest()
        with self.assertRaises(ArtifactError):
            verify_artifacts(self.root)

        (self.root / "manifest.json").write_text('{"version":1,"version":1}')
        with self.assertRaises(ArtifactError):
            verify_artifacts(self.root)

    def test_unlisted_encoder_weight_cannot_override_manifest(self):
        (self.root / "dinov2/pytorch_model.bin").write_bytes(b"unverified")
        with self.assertRaises(ArtifactError):
            verify_artifacts(self.root)


class ModelsCommandTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Isolated worker checkout lacks the integration owner's package __init__.
        source = Path(__file__).resolve().parents[2] / "src/navcore/cli/models.py"
        spec = importlib.util.spec_from_file_location("test_only_models_cli", source)
        cls.models = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.models)

    def test_parser_and_exporter_version_gate(self):
        parser = argparse.ArgumentParser()
        self.models.register_models(parser.add_subparsers(dest="command"))
        args = parser.parse_args(["models-fetch", "--model-dir", "/tmp/models"])
        self.assertEqual(args.model_dir, Path("/tmp/models"))
        self.assertIsNone(args.export_python)
        result = subprocess.CompletedProcess([], 0, json.dumps(self.models.EXPORT_PACKAGES), "")
        with patch.object(self.models.subprocess, "run", return_value=result):
            self.models._export_preflight(Path("/private/export/python"))
        result.stdout = json.dumps({**self.models.EXPORT_PACKAGES, "onnx": "wrong"})
        with patch.object(self.models.subprocess, "run", return_value=result):
            with self.assertRaises(ArtifactError):
                self.models._export_preflight(Path("/private/export/python"))

    def test_download_hash_mismatch_removes_only_its_temporary_file(self):
        content = b"verified-test-artifact"
        transport = httpx.MockTransport(lambda request: httpx.Response(200, content=content))
        with (
            tempfile.TemporaryDirectory() as temporary,
            httpx.Client(transport=transport) as client,
        ):
            root = Path(temporary)
            with self.assertRaises(ArtifactError):
                self.models._download(
                    client,
                    root,
                    "artifact.bin",
                    "https://example.test/model",
                    len(content),
                    "a" * 64,
                )
            self.assertEqual(list(root.iterdir()), [])
            metadata = self.models._download(
                client,
                root,
                "artifact.bin",
                "https://example.test/model",
                len(content),
                hashlib.sha256(content).hexdigest(),
            )
            self.assertEqual(metadata["bytes"], len(content))
            self.assertEqual((root / "artifact.bin").stat().st_mode & 0o777, 0o644)
            (root / "artifact.bin").write_bytes(b"user-owned-data")
            with self.assertRaises(ArtifactError):
                self.models._download(
                    client,
                    root,
                    "artifact.bin",
                    "https://example.test/model",
                    len(content),
                    "a" * 64,
                )
            self.assertEqual((root / "artifact.bin").read_bytes(), b"user-owned-data")


if __name__ == "__main__":
    unittest.main()
