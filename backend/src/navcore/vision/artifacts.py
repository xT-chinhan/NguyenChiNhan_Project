"""Pinned artifact metadata and read-only verification; never downloads at startup."""

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

DINO_REPOSITORY = "facebook/dinov2-base"
DINO_REVISION = "f9e44c814b77203eaa57a6bdbbd535f21ede1415"
DINO_URL = f"https://huggingface.co/{DINO_REPOSITORY}/resolve/{DINO_REVISION}"
PREPROCESS_VERSION = "rgb-upright-jpeg90-dinov2-processor-slow-v1"
YOLO_URL = "https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo26n.pt"
YOLO_SHA256 = "9b09cc8bf347f0fc8a5f7657480587f25db09b34bf33b0652110fb03a8ad4fef"
YOLO_BYTES = 5_544_453
EXPORT_OPTIONS = {
    "imgsz": 224,
    "opset": 17,
    "batch": 1,
    "dynamic": False,
    "end2end": True,
    "nms": False,
    "simplify": False,
    "half": False,
    "int8": False,
}
COCO_LABELS = (
    "person",
    "bicycle",
    "car",
    "motorcycle",
    "airplane",
    "bus",
    "train",
    "truck",
    "boat",
    "traffic light",
    "fire hydrant",
    "stop sign",
    "parking meter",
    "bench",
    "bird",
    "cat",
    "dog",
    "horse",
    "sheep",
    "cow",
    "elephant",
    "bear",
    "zebra",
    "giraffe",
    "backpack",
    "umbrella",
    "handbag",
    "tie",
    "suitcase",
    "frisbee",
    "skis",
    "snowboard",
    "sports ball",
    "kite",
    "baseball bat",
    "baseball glove",
    "skateboard",
    "surfboard",
    "tennis racket",
    "bottle",
    "wine glass",
    "cup",
    "fork",
    "knife",
    "spoon",
    "bowl",
    "banana",
    "apple",
    "sandwich",
    "orange",
    "broccoli",
    "carrot",
    "hot dog",
    "pizza",
    "donut",
    "cake",
    "chair",
    "couch",
    "potted plant",
    "bed",
    "dining table",
    "toilet",
    "tv",
    "laptop",
    "mouse",
    "remote",
    "keyboard",
    "cell phone",
    "microwave",
    "oven",
    "toaster",
    "sink",
    "refrigerator",
    "book",
    "clock",
    "vase",
    "scissors",
    "teddy bear",
    "hair drier",
    "toothbrush",
)


class ArtifactError(ValueError):
    pass


@dataclass(frozen=True)
class Artifacts:
    encoder_dir: Path
    detector_path: Path
    encoder_fingerprint: str
    labels: tuple[str, ...]
    manifest: dict


def safe_path(root: Path, relative: str) -> Path:
    """Confine manifest paths and reject existing symlinks, including root ancestors."""
    root = Path(root)
    if not root.is_absolute() or not isinstance(relative, str) or "\\" in relative:
        raise ArtifactError("Invalid artifact path")
    parts = PurePosixPath(relative).parts
    if (
        not parts
        or relative.startswith("/")
        or "\x00" in relative
        or any(part in {"", ".", ".."} for part in relative.split("/"))
    ):
        raise ArtifactError("Invalid artifact path")
    candidate = root.joinpath(*parts)
    for path in (candidate, *candidate.parents):
        if path.is_symlink():
            raise ArtifactError("Artifact symlinks are not allowed")
    return candidate


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _unique_object(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ArtifactError("Duplicate manifest key")
        result[key] = value
    return result


def read_json(path: Path, limit: int = 1_048_576) -> dict:
    try:
        with path.open("rb") as stream:
            data = stream.read(limit + 1)
        if len(data) > limit:
            raise ArtifactError("Artifact metadata exceeds limit")
        value = json.loads(
            data,
            object_pairs_hook=_unique_object,
            parse_constant=lambda _: (_ for _ in ()).throw(ArtifactError("Invalid JSON constant")),
        )
        if not isinstance(value, dict):
            raise ArtifactError("Invalid artifact metadata")
        return value
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise ArtifactError("Cannot read artifact metadata") from None


def encoder_files(files: dict) -> None:
    if (
        not isinstance(files, dict)
        or not {"config.json", "preprocessor_config.json"} <= files.keys()
    ):
        raise ArtifactError("Missing encoder metadata")
    if "model.safetensors" in files:
        if set(files) != {"config.json", "preprocessor_config.json", "model.safetensors"}:
            raise ArtifactError("Unexpected encoder files")
    else:
        shards = set(files) - {
            "config.json",
            "preprocessor_config.json",
            "model.safetensors.index.json",
        }
        if (
            "model.safetensors.index.json" not in files
            or not 1 <= len(shards) <= 128
            or any(not re.fullmatch(r"model-\d{5}-of-\d{5}\.safetensors", s) for s in shards)
        ):
            raise ArtifactError("Invalid safetensors shard set")


def _verify_file(path: Path, metadata: dict) -> None:
    if (
        not isinstance(metadata, dict)
        or type(metadata.get("bytes")) is not int
        or not 0 < metadata["bytes"] <= 2_147_483_648
        or not isinstance(metadata.get("sha256"), str)
        or not re.fullmatch(r"[0-9a-f]{64}", metadata["sha256"])
    ):
        raise ArtifactError("Invalid artifact hash metadata")
    try:
        if (
            not path.is_file()
            or path.stat().st_size != metadata["bytes"]
            or file_sha256(path) != metadata["sha256"]
        ):
            raise ArtifactError("Artifact integrity mismatch")
    except OSError:
        raise ArtifactError("Cannot read artifact") from None


def encoder_fingerprint(encoder: dict) -> str:
    identity = {key: encoder[key] for key in ("repository", "revision", "preprocess_version")}
    identity["files"] = {
        name: {key: meta[key] for key in ("sha256", "bytes")}
        for name, meta in encoder["files"].items()
    }
    return hashlib.sha256(
        json.dumps(identity, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    ).hexdigest()


def verify_artifacts(root: Path) -> Artifacts:
    root = Path(root)
    manifest = read_json(safe_path(root, "manifest.json"))
    try:
        encoder, detector = manifest["encoder"], manifest["detector"]
        if (
            type(manifest.get("version")) is not int
            or manifest["version"] != 1
            or encoder["repository"] != DINO_REPOSITORY
            or encoder["revision"] != DINO_REVISION
            or encoder["preprocess_version"] != PREPROCESS_VERSION
            or encoder["license"] != "Apache-2.0"
        ):
            raise ArtifactError("Unsupported encoder identity")
        encoder_files(encoder["files"])
        encoder_dir = safe_path(root, "dinov2")
        if {entry.name for entry in encoder_dir.iterdir()} != set(encoder["files"]):
            raise ArtifactError("Unlisted files in encoder directory")
        for name, metadata in encoder["files"].items():
            if metadata.get("url") != f"{DINO_URL}/{name}":
                raise ArtifactError("Unexpected encoder source")
            _verify_file(safe_path(root, f"dinov2/{name}"), metadata)
        if "model.safetensors.index.json" in encoder["files"]:
            index = read_json(safe_path(root, "dinov2/model.safetensors.index.json"), 4_194_304)
            mapping = index.get("weight_map")
            shards = set(encoder["files"]) - {
                "config.json",
                "preprocessor_config.json",
                "model.safetensors.index.json",
            }
            if not isinstance(mapping, dict) or not mapping or set(mapping.values()) != shards:
                raise ArtifactError("Invalid safetensors index")
        config = read_json(safe_path(root, "dinov2/config.json"))
        if config.get("model_type") != "dinov2" or config.get("hidden_size") != 768:
            raise ArtifactError("Unexpected encoder architecture")
        if (
            detector["path"] != "yolo/yolo26n.onnx"
            or detector["source_url"] != YOLO_URL
            or detector["source_sha256"] != YOLO_SHA256
            or detector["source_bytes"] != YOLO_BYTES
            or detector["input"] != [1, 3, 224, 224]
            or detector["output"] != [1, 300, 6]
            or detector["dtype"] != "float32"
            or detector["labels"] != list(COCO_LABELS)
            or detector["license"] != "AGPL-3.0-or-Enterprise"
            or detector["export"]["options"] != EXPORT_OPTIONS
            or detector["export"]["versions"]["ultralytics"] != "8.4.183"
            or detector["export"]["versions"]["onnx"] != "1.23.2"
            or detector["export"]["parity"]["passed"] is not True
            or not 299 <= detector["export"]["parity"].get("matched_rows", 0) <= 300
            or detector["export"]["parity"].get("cutoff_tied_rows")
            != 300 - detector["export"]["parity"].get("matched_rows", 0)
        ):
            raise ArtifactError("Unexpected detector identity")
        detector_path = safe_path(root, detector["path"])
        _verify_file(detector_path, detector)
        return Artifacts(
            encoder_dir, detector_path, encoder_fingerprint(encoder), COCO_LABELS, manifest
        )
    except (KeyError, TypeError, AttributeError, ValueError) as error:
        if isinstance(error, ArtifactError):
            raise
        raise ArtifactError("Invalid artifact manifest") from None
