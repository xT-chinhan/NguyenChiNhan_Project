"""Explicit model acquisition/export commands, separate from server startup."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import httpx

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
    encoder_files,
    file_sha256,
    read_json,
    safe_path,
)

EXPORT_SCRIPT = r"""
import hashlib, importlib.metadata, json, os, sys
from pathlib import Path
os.environ['YOLO_AUTOINSTALL'] = 'false'
os.environ['YOLO_OFFLINE'] = 'true'
import numpy as np
import onnx
import onnxruntime as ort
import torch
from ultralytics import YOLO
root = Path(sys.argv[1])
pt = root / 'yolo/yolo26n.pt'
if hashlib.sha256(pt.read_bytes()).hexdigest() != sys.argv[2]:
    raise RuntimeError('Unverified exporter source')
model = YOLO(str(pt))
model.model.float().eval()
# The exporter selects the one-to-one head on its own copy; parity must use that same head.
model.model.end2end = True
options = json.loads(sys.argv[3])
exported = Path(model.export(format='onnx', device='cpu', **options))
if exported != root / 'yolo/yolo26n.onnx':
    raise RuntimeError('Unexpected export destination')
graph = onnx.load(str(exported), load_external_data=False)
onnx.checker.check_model(graph)
if any(t.data_location == onnx.TensorProto.EXTERNAL for t in graph.graph.initializer):
    raise RuntimeError('External ONNX data is unsupported')
if any(t.data_type == onnx.TensorProto.FLOAT16 for t in graph.graph.initializer):
    raise RuntimeError('FP16 export is unsupported')
session = ort.InferenceSession(str(exported), providers=['CPUExecutionProvider'])
ins, outs = session.get_inputs(), session.get_outputs()
assert len(ins) == len(outs) == 1
assert ins[0].shape == [1,3,224,224] and ins[0].type == 'tensor(float)'
assert outs[0].shape == [1,300,6] and outs[0].type == 'tensor(float)'
smoke = np.random.default_rng(0).random((1,3,224,224), dtype=np.float32)
with torch.inference_mode():
    expected = model.model(torch.from_numpy(smoke))
while isinstance(expected, (tuple,list)):
    expected = expected[0]
expected = expected.detach().cpu().numpy()
actual = session.run(None, {ins[0].name: smoke})[0]
assert expected.shape == actual.shape == (1,300,6)
assert np.isfinite(expected).all() and np.isfinite(actual).all()
sys.path.insert(0, sys.argv[4])
from navcore.cli.export_parity import compare_predictions
parity = compare_predictions(expected, actual)
parity['fixture'] = 'numpy-default_rng-0-rgb-float32-224'
names = [model.names[i] for i in range(80)]
report = {'versions': {d.metadata['Name'].lower(): d.version
                       for d in importlib.metadata.distributions()},
          'options': options, 'labels': names,
          'parity': parity}
with (root / 'yolo/export.json').open('x') as stream:
    json.dump(report, stream, sort_keys=True, allow_nan=False)
"""

EXPORT_PACKAGES = {
    "ultralytics": "8.4.183",
    "onnx": "1.23.2",
    "onnxruntime": "1.31.0",
    "torch": "2.13.0",
    "torchvision": "0.28.0",
}


def register_models(commands: argparse._SubParsersAction) -> None:
    for name in ("models-fetch", "models-verify"):
        parser = commands.add_parser(
            name,
            help="Fetch/export models"
            if name.endswith("fetch")
            else "Verify local models without network access",
        )
        parser.add_argument("--model-dir", type=Path, required=True)
        if name.endswith("fetch"):
            parser.add_argument("--export-python", type=Path)


def _export_preflight(python: Path) -> None:
    code = (
        "import importlib.metadata as m,json; "
        f"print(json.dumps({{p:m.version(p) for p in {list(EXPORT_PACKAGES)!r}}}))"
    )
    try:
        result = subprocess.run(
            [str(python), "-c", code], check=True, capture_output=True, text=True, timeout=30
        )
        versions = json.loads(result.stdout)
        if any(
            versions.get(name, "").split("+")[0] != version
            for name, version in EXPORT_PACKAGES.items()
        ):
            raise ArtifactError("Exporter versions do not match the pinned tool environment")
    except (OSError, subprocess.SubprocessError, ValueError):
        raise ArtifactError("Pinned exporter environment is unavailable") from None


def _remote_json(client: httpx.Client, url: str) -> dict:
    data = bytearray()
    with client.stream("GET", url) as response:
        response.raise_for_status()
        if response.url.scheme != "https":
            raise ArtifactError("Insecure artifact redirect")
        for chunk in response.iter_bytes():
            data.extend(chunk)
            if len(data) > 1_048_576:
                raise ArtifactError("Remote artifact metadata exceeds limit")
    value = json.loads(data)
    if not isinstance(value, dict):
        raise ArtifactError("Invalid remote metadata")
    return value


def _download(
    client: httpx.Client,
    root: Path,
    relative: str,
    url: str,
    expected_size: int,
    expected_sha: str | None = None,
    expected_git_blob: str | None = None,
) -> dict:
    destination = safe_path(root, relative)
    if type(expected_size) is not int or not 0 < expected_size <= 2_147_483_648:
        raise ArtifactError("Invalid artifact download size")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        if not destination.exists():
            with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as stream:
                temporary = Path(stream.name)
                size = 0
                with client.stream("GET", url) as response:
                    response.raise_for_status()
                    if response.url.scheme != "https":
                        raise ArtifactError("Insecure artifact redirect")
                    for chunk in response.iter_bytes(chunk_size=1024 * 1024):
                        size += len(chunk)
                        if size > expected_size:
                            raise ArtifactError("Artifact exceeds declared size")
                        stream.write(chunk)
            candidate = temporary
        else:
            candidate = destination
        if candidate.stat().st_size != expected_size:
            raise ArtifactError("Artifact byte count mismatch")
        sha = file_sha256(candidate)
        if expected_sha is not None:
            if sha != expected_sha:
                raise ArtifactError("Artifact checksum mismatch")
        elif expected_git_blob is not None:
            digest = hashlib.sha1(f"blob {expected_size}\0".encode(), usedforsecurity=False)
            with candidate.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != expected_git_blob:
                raise ArtifactError("Pinned revision blob mismatch")
        else:
            raise ArtifactError("Missing pinned artifact checksum")
        if temporary is not None:
            # Another invocation must not overwrite an artifact created during this download.
            temporary.chmod(0o644)
            os.link(temporary, destination)
        return {"url": url, "bytes": expected_size, "sha256": sha}
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def fetch_models(model_dir: Path, export_python: Path | None = None) -> None:
    root = Path(model_dir).absolute()
    safe_path(root, "manifest.json")
    python = export_python or Path(__file__).resolve().parents[3] / ".venv-export/bin/python"
    if (root / "manifest.json").exists():
        verify_models(root)
        return
    _export_preflight(python)
    root.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(root).free < 4 * 1024**3:
        raise ArtifactError("Model preparation must preserve 4 GiB free disk")
    encoder = {
        "repository": DINO_REPOSITORY,
        "revision": DINO_REVISION,
        "preprocess_version": PREPROCESS_VERSION,
        "license": "Apache-2.0",
        "files": {},
    }
    with httpx.Client(follow_redirects=True, timeout=120) as client:
        metadata = _remote_json(
            client,
            f"https://huggingface.co/api/models/{DINO_REPOSITORY}"
            f"/revision/{DINO_REVISION}?blobs=true",
        )
        if metadata.get("sha") != DINO_REVISION:
            raise ArtifactError("Hugging Face revision mismatch")
        siblings = {entry["rfilename"]: entry for entry in metadata["siblings"]}

        def download_encoder(name: str) -> None:
            safe_path(root, name)
            entry = siblings[name]
            if shutil.disk_usage(root).free - entry["size"] < 4 * 1024**3 + 67_108_864:
                raise ArtifactError("Model download would exceed the local disk budget")
            lfs = entry.get("lfs") or {}
            encoder["files"][name] = _download(
                client,
                root,
                f"dinov2/{name}",
                f"{DINO_URL}/{name}",
                entry["size"],
                lfs.get("sha256"),
                entry.get("blobId"),
            )

        for name in ("config.json", "preprocessor_config.json"):
            download_encoder(name)
        if "model.safetensors" in siblings:
            download_encoder("model.safetensors")
        else:
            download_encoder("model.safetensors.index.json")
            index = read_json(safe_path(root, "dinov2/model.safetensors.index.json"), 4_194_304)
            mapping = index.get("weight_map")
            if not isinstance(mapping, dict) or not mapping:
                raise ArtifactError("Invalid safetensors index")
            files = {**encoder["files"], **{name: {} for name in set(mapping.values())}}
            encoder_files(files)
            for name in sorted(set(mapping.values())):
                download_encoder(name)
        encoder_files(encoder["files"])
        _download(client, root, "yolo/yolo26n.pt", YOLO_URL, YOLO_BYTES, YOLO_SHA256)
    for relative in ("yolo/yolo26n.onnx", "yolo/export.json"):
        path = safe_path(root, relative)
        if path.exists():
            raise ArtifactError("Export output already exists without a completed manifest")
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith(("NAV_", "POSTGRES_"))
    }
    environment.update(
        {
            "YOLO_AUTOINSTALL": "false",
            "YOLO_OFFLINE": "true",
            "YOLO_CONFIG_DIR": str(root / "yolo" / "export-config"),
        }
    )
    try:
        subprocess.run(
            [
                str(python),
                "-c",
                EXPORT_SCRIPT,
                str(root),
                YOLO_SHA256,
                json.dumps(EXPORT_OPTIONS),
                str(Path(__file__).resolve().parents[2]),
            ],
            check=True,
            env=environment,
            capture_output=True,
            text=True,
            timeout=1800,
        )
    except (OSError, subprocess.SubprocessError):
        raise ArtifactError("ONNX export or parity check failed") from None
    report = read_json(safe_path(root, "yolo/export.json"))
    if report.pop("labels", None) != list(COCO_LABELS):
        raise ArtifactError("Unexpected COCO label mapping")
    onnx = safe_path(root, "yolo/yolo26n.onnx")
    detector = {
        "path": "yolo/yolo26n.onnx",
        "sha256": file_sha256(onnx),
        "bytes": onnx.stat().st_size,
        "source_url": YOLO_URL,
        "source_sha256": YOLO_SHA256,
        "source_bytes": YOLO_BYTES,
        "license": "AGPL-3.0-or-Enterprise",
        "dtype": "float32",
        "input": [1, 3, 224, 224],
        "output": [1, 300, 6],
        "labels": list(COCO_LABELS),
        "export": report,
    }
    manifest = {"version": 1, "encoder": encoder, "detector": detector}
    with safe_path(root, "manifest.json").open("x", encoding="utf-8") as stream:
        json.dump(manifest, stream, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")
    verify_models(root)


def verify_models(model_dir: Path) -> str:
    from navcore.vision.pipeline import VisionPipeline

    pipeline = VisionPipeline.from_model_dir(Path(model_dir).absolute(), device="cpu")
    return pipeline.encoder_fingerprint


def run_models(args: argparse.Namespace) -> None:
    try:
        if args.command == "models-fetch":
            fetch_models(args.model_dir, args.export_python)
            print("Model preparation and verification passed")
        else:
            fingerprint = verify_models(args.model_dir)
            print(f"Model verification passed; encoder fingerprint {fingerprint}")
    except (ArtifactError, OSError, ValueError, KeyError, httpx.HTTPError) as error:
        raise SystemExit(
            "Model preparation/verification failed: "
            + (
                str(error)
                if isinstance(error, ArtifactError)
                else "artifact or model contract error"
            )
        ) from None
