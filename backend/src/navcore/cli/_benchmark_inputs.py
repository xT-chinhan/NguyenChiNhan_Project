"""Private credentials, confined prepared frames and exact source-bound identities."""

import hashlib
import io
import json
import math
import os
import re
import stat
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit
from uuid import UUID

from PIL import Image

from navcore.core.policy import BASELINE
from navcore.vision.artifacts import file_sha256, read_json
from navcore.vision.images import decode_image

SERVER_INPUT_KEYS = (
    "source_sha256",
    "uv_lock_sha256",
    "model_manifest_sha256",
    "policy_sha256",
)
HASH = re.compile(r"[0-9a-f]{64}\Z")


def validate_api_url(value: str) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
        or any(char.isspace() for char in value)
    ):
        raise ValueError("API URL must be an HTTP origin without credentials")
    try:
        _ = parsed.port
    except ValueError:
        raise ValueError("Invalid API port") from None
    return urlunsplit((parsed.scheme, parsed.netloc, "", "", ""))


def _no_symlinks(path: Path) -> None:
    if any(item.is_symlink() for item in (path, *path.parents)):
        raise ValueError("Input symlinks are not allowed")


@dataclass(frozen=True, repr=False)
class Device:
    api_url: str
    token: str


def load_devices(directory: Path, sessions: int) -> list[Device]:
    directory = directory.absolute()
    _no_symlinks(directory)
    paths = sorted(directory.glob("*.env"))
    for path in paths:
        _no_symlinks(path)
    if sessions not in {1, 4} or len(paths) not in {1, 4}:
        raise ValueError("Device directory must contain one or four env files")
    if sessions == 4 and len(paths) != 4:
        raise ValueError("Four sessions require four device files")
    devices = []
    for path in paths:
        _no_symlinks(path)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as stream:
            metadata = os.fstat(stream.fileno())
            if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
                raise ValueError("Device files require regular files with mode 0600")
            if metadata.st_uid != os.getuid() or metadata.st_size > 4096:
                raise ValueError("Invalid device file ownership or size")
            data = stream.read(4097)
            if len(data) > 4096:
                raise ValueError("Device file exceeds size limit")
            try:
                text = data.decode("utf-8")
            except UnicodeError:
                raise ValueError("Invalid device file encoding") from None
            values = {}
            for line in text.splitlines():
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                key, separator, value = line.partition("=")
                if separator != "=" or key in values:
                    raise ValueError("Invalid device env format")
                values[key] = value
        if set(values) != {"NAV_API_URL", "NAV_DEVICE_TOKEN"} or not re.fullmatch(
            r"navdev_[A-Za-z0-9_-]{43}", values.get("NAV_DEVICE_TOKEN", "")
        ):
            raise ValueError("Invalid device env fields")
        devices.append(Device(validate_api_url(values["NAV_API_URL"]), values["NAV_DEVICE_TOKEN"]))
    if len({device.token for device in devices}) != len(devices):
        raise ValueError("Device tokens must be distinct")
    if len({device.api_url for device in devices}) != 1:
        raise ValueError("Device API origins must agree")
    return devices[:sessions]


def confined_path(root: Path, relative: str) -> Path:
    if (
        not isinstance(relative, str)
        or "\\" in relative
        or "\x00" in relative
        or Path(relative).is_absolute()
        or any(part in {"", ".", ".."} for part in relative.split("/"))
    ):
        raise ValueError("Invalid prepared-frame path")
    candidate = root / relative
    _no_symlinks(candidate)
    if not candidate.is_file() or not candidate.resolve().is_relative_to(root.resolve()):
        raise ValueError("Prepared frame is outside dataset")
    return candidate


@dataclass
class FrameDataset:
    root: Path
    samples: list[dict]
    duration_ms: float
    jsonl_sha256: str
    source_manifest_sha256: str | None
    dimensions: set[tuple[int, int]] = field(default_factory=set)

    @classmethod
    def load(cls, path: Path):
        path = path.absolute()
        _no_symlinks(path)
        if not path.is_file() or path.stat().st_size > 16_777_216:
            raise ValueError("Invalid prepared-frame JSONL size")
        samples = []
        with path.open("rb") as stream:
            for line in stream:
                if len(line) > 4096 or len(samples) >= 50_000:
                    raise ValueError("Prepared-frame metadata exceeds limit")
                try:
                    entry = json.loads(line)
                except (UnicodeError, json.JSONDecodeError):
                    raise ValueError("Invalid prepared-frame JSONL") from None
                if (
                    not isinstance(entry, dict)
                    or set(entry) != {"sample_index", "pts_ms", "relative_path", "pixel_sha256"}
                    or type(entry["sample_index"]) is not int
                    or entry["sample_index"] != len(samples)
                    or type(entry["pts_ms"]) not in {int, float}
                    or not math.isfinite(entry["pts_ms"])
                    or entry["pts_ms"] < 0
                    or (samples and entry["pts_ms"] <= samples[-1]["pts_ms"])
                    or not isinstance(entry["pixel_sha256"], str)
                    or not HASH.fullmatch(entry["pixel_sha256"])
                ):
                    raise ValueError("Invalid prepared-frame metadata")
                confined_path(path.parent, entry["relative_path"])
                samples.append(entry)
        if not samples or samples[0]["pts_ms"] != 0:
            raise ValueError("Prepared frames must start at zero")
        source = path.parent / "source-manifest.json"
        source_hash = None
        duration = samples[-1]["pts_ms"] + 200
        if source.exists():
            _no_symlinks(source)
            metadata = read_json(source)
            if metadata.get("frames_sha256") != file_sha256(path):
                raise ValueError("Prepared-frame manifest integrity mismatch")
            source_hash = file_sha256(source)
        return cls(path.parent, samples, duration, file_sha256(path), source_hash)

    def jpeg(self, elapsed_ms: float) -> bytes:
        """Replay loops prepared pixels; capture timestamp is assigned after this decode."""
        from bisect import bisect_right

        position = elapsed_ms % self.duration_ms
        index = max(0, bisect_right(self.samples, position, key=lambda row: row["pts_ms"]) - 1)
        sample = self.samples[index]
        path = confined_path(self.root, sample["relative_path"])
        if path.stat().st_size > 393_216:
            raise ValueError("Prepared JPEG exceeds frame byte limit")
        decoded = decode_image(path.read_bytes())
        if decoded.pixel_sha256 != sample["pixel_sha256"]:
            raise ValueError("Prepared-frame pixel integrity mismatch")
        height, width = decoded.rgb.shape[:2]
        if width > 640 or height > 480:
            raise ValueError("Benchmark frames must fit 640x480")
        self.dimensions.add((width, height))
        output = io.BytesIO()
        Image.fromarray(decoded.rgb).save(output, format="JPEG", quality=75, exif=b"")
        data = output.getvalue()
        if len(data) > 393_216:
            raise ValueError("Benchmark JPEG exceeds frame byte limit")
        return data


def source_files(backend_root: Path) -> dict[str, str]:
    """Hash actual bytes including uncommitted files; no dependency caches or model data."""
    root = backend_root.absolute()
    files = []
    for directory in ("src", "migrations", "scripts", "config", "tests"):
        base = root / directory
        if base.exists():
            files.extend(
                path
                for path in base.rglob("*")
                if path.is_file()
                and (
                    path.suffix
                    in {
                        ".py",
                        ".sh",
                        ".toml",
                        ".ini",
                        ".mako",
                        ".yaml",
                        ".yml",
                        ".html",
                        ".css",
                        ".js",
                        ".mjs",
                    }
                    or (
                        "fixtures/synthetic" in path.as_posix()
                        and path.suffix in {".json", ".jsonl"}
                    )
                )
                and "__pycache__" not in path.parts
            )
    files.extend(
        path
        for path in (
            root / "pyproject.toml",
            root / "uv.lock",
            root / "Dockerfile",
            root / ".dockerignore",
            root / "config/.env.example",
            root / "config/exporter/uv.lock",
        )
        if path.is_file()
    )
    result = {}
    for path in sorted(set(files)):
        _no_symlinks(path)
        result[path.relative_to(root).as_posix()] = file_sha256(path)
    if not result:
        raise ValueError("No backend source files found")
    return result


def source_identity(backend_root: Path) -> str:
    return hashlib.sha256(
        json.dumps(source_files(backend_root), sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def build_input_identity(backend_root: Path, model_dir: Path, dataset_manifest=None) -> dict:
    files = source_files(backend_root)

    def optional(path):
        return file_sha256(path) if path.is_file() else None

    return {
        "source_sha256": source_identity(backend_root),
        "source_files_sha256": files,
        "uv_lock_sha256": optional(backend_root / "uv.lock"),
        "model_manifest_sha256": optional(model_dir / "manifest.json"),
        "policy_sha256": BASELINE.fingerprint,
        "dataset_manifest_sha256": optional(dataset_manifest) if dataset_manifest else None,
    }


def process_identity(pid: int) -> dict:
    # Field 22 follows the parenthesized comm field, which can itself contain spaces.
    proc = Path("/proc") / str(pid)
    tail = (proc / "stat").read_text().rsplit(")", 1)[1].split()
    return {
        "pid": pid,
        "start_ticks": tail[19],
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "cmdline_sha256": file_sha256(proc / "cmdline"),
    }


def _workload_identity(value) -> dict | None:
    try:
        count, references = value["checkpoint_count"], value["reference_counts"]
        if (
            type(count) is not int
            or not 2 <= count <= 64
            or not isinstance(references, list)
            or len(references) != count
            or any(type(item) is not int or not 3 <= item <= 8 for item in references)
            or not HASH.fullmatch(value["route_fingerprint"])
        ):
            return None
        return {
            "route_id": str(UUID(value["route_id"])),
            "checkpoint_count": count,
            "reference_counts": references,
            "route_fingerprint": value["route_fingerprint"],
        }
    except (ValueError, TypeError, KeyError, AttributeError):
        return None


def check_attestation(path, inputs: dict, api_url: str, profile: str, backend_pid=None) -> dict:
    blocked = {"status": "BLOCKED_ATTESTATION", "adapter_kind": "unverified"}
    if path is None:
        return {**blocked, "reason": "No operator-local server receipt supplied"}
    try:
        receipt = read_json(Path(path))
        UUID(receipt["server_instance_id"])
        if (
            receipt.get("schema_version") != 1
            or receipt.get("attestation_kind") != "operator_local"
            or validate_api_url(receipt["api_url"]) != validate_api_url(api_url)
            or receipt.get("profile") != profile
            or receipt.get("adapter_kind") not in {"real_models", "synthetic"}
            or any(
                not isinstance(inputs.get(key), str)
                or not HASH.fullmatch(inputs[key])
                or receipt["inputs"].get(key) != inputs[key]
                for key in SERVER_INPUT_KEYS
            )
            or (backend_pid is not None and receipt.get("process") != process_identity(backend_pid))
        ):
            return {**blocked, "reason": "Server receipt identity or input hashes differ"}
        return {
            "status": "MATCHED_OPERATOR_ATTESTATION",
            "adapter_kind": receipt["adapter_kind"],
            "server_instance_id": receipt["server_instance_id"],
            "receipt_sha256": file_sha256(Path(path)),
            "server_profile": profile,
            "process": process_identity(backend_pid) if backend_pid is not None else None,
            "workload": _workload_identity(receipt.get("workload")),
        }
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError):
        return {**blocked, "reason": "Invalid operator-local server receipt"}
