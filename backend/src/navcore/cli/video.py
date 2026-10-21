"""Explicit, source-preserving video sampling and bounded replay image loading."""

import bisect
import io
import json
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from navcore.cli.bundle import confined_file, file_sha256, read_json
from navcore.vision.images import MAX_IMAGE_BYTES, decode_image


@dataclass(frozen=True)
class FrameSample:
    sample_index: int
    pts_ms: float
    relative_path: str
    pixel_sha256: str


@dataclass(frozen=True)
class PlaybackFrames:
    root: Path
    samples: tuple[FrameSample, ...]
    source_manifest: dict

    def choose(self, elapsed_ms: float, after_index: int = -1) -> FrameSample | None:
        index = bisect.bisect_right([sample.pts_ms for sample in self.samples], elapsed_ms) - 1
        if index <= after_index or index < 0:
            return None
        return self.samples[index]

    def decode(self, sample: FrameSample) -> bytes:
        path = confined_file(self.root, sample.relative_path)
        if path.stat().st_size > MAX_IMAGE_BYTES:
            raise ValueError("Oversized prepared JPEG")
        decoded = decode_image(path.read_bytes())
        if decoded.pixel_sha256 != sample.pixel_sha256:
            raise ValueError("Prepared frame pixels changed")
        buffer = io.BytesIO()
        Image.fromarray(decoded.rgb).save(buffer, format="JPEG", quality=75, exif=b"")
        jpeg = buffer.getvalue()
        if len(jpeg) > MAX_IMAGE_BYTES:
            raise ValueError("Encoded replay JPEG is oversized")
        return jpeg


def load_frames(path: Path) -> PlaybackFrames:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("Missing or oversized frames manifest")
    root = path.absolute().parent
    if any(parent.is_symlink() for parent in (root, *root.parents)):
        raise ValueError("Prepared frame ancestors must not be symlinks")
    source = read_json(root / "source-manifest.json")
    if (
        source.get("schema_version") != 1
        or source.get("fps") != 5
        or source.get("frames_sha256") != file_sha256(path)
    ):
        raise ValueError("Invalid prepared source manifest")
    duration = source.get("duration_ms")
    if (
        isinstance(duration, bool)
        or not isinstance(duration, (int, float))
        or not math.isfinite(duration)
        or duration <= 0
    ):
        raise ValueError("Invalid prepared video duration")
    samples = []
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if len(line) > 2048 or len(samples) >= 18000:
                raise ValueError("Prepared sample manifest is oversized")
            row = json.loads(line)
            if set(row) != {"sample_index", "pts_ms", "relative_path", "pixel_sha256"}:
                raise ValueError("Invalid prepared sample fields")
            index, pts, pixel = row["sample_index"], row["pts_ms"], row["pixel_sha256"]
            if (
                type(index) is not int
                or index != len(samples)
                or isinstance(pts, bool)
                or not isinstance(pts, (int, float))
                or not math.isfinite(pts)
                or pts != index * 200
            ):
                raise ValueError("Prepared sample ordering must be 5 fps")
            if (
                not isinstance(pixel, str)
                or len(pixel) != 64
                or any(c not in "0123456789abcdef" for c in pixel)
            ):
                raise ValueError("Invalid prepared pixel hash")
            confined_file(root, row["relative_path"])
            samples.append(FrameSample(**row))
    if not samples or samples[-1].pts_ms > duration:
        raise ValueError("Prepared samples missing or outside source duration")
    return PlaybackFrames(root, tuple(samples), source)


def _run(argv: list[str], timeout: int) -> subprocess.CompletedProcess:
    result = subprocess.run(
        argv,
        shell=False,
        stdout=subprocess.PIPE if argv[0] == "ffprobe" else subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
        check=False,
    )
    if result.returncode:
        raise ValueError("Video tool failed")
    return result


def prepare_video(source: Path, output: Path) -> Path:
    source = source.resolve(strict=True)
    if not source.is_file():
        raise ValueError("Video input must be a file")
    if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
        raise ValueError("Video output directory must be empty")
    output = output.absolute()
    if any(parent.is_symlink() for parent in (output.parent, *output.parent.parents)):
        raise ValueError("Video output ancestors must not be symlinks")
    original_hash = file_sha256(source)
    probe = _run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,start_time,duration:format=duration",
            "-of",
            "json",
            str(source),
        ],
        30,
    )
    metadata = json.loads(probe.stdout)
    streams = metadata.get("streams", [])
    if not streams:
        raise ValueError("No video stream")
    duration = float(streams[0].get("duration", metadata.get("format", {}).get("duration", 0)))
    if not math.isfinite(duration) or not 0 < duration <= 3600:
        raise ValueError("Video duration must be positive and at most one hour")
    output.mkdir(parents=True, exist_ok=True)
    # ffmpeg autorotate applies display-matrix/rotation metadata before filters.
    # Normalized PTS is the replay clock; source start PTS is retained below.
    _run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-i",
            str(source),
            "-map",
            "0:v:0",
            "-an",
            "-sn",
            "-dn",
            "-vf",
            "setpts=PTS-STARTPTS,fps=5,scale=w='min(640,iw)':h='min(480,ih)':force_original_aspect_ratio=decrease",
            "-fps_mode",
            "passthrough",
            "-q:v",
            "3",
            "-start_number",
            "0",
            "-n",
            str(output / "frame-%06d.jpg"),
        ],
        max(60, int(duration * 5)),
    )
    rows = []
    for index, path in enumerate(sorted(output.glob("frame-*.jpg"))):
        decoded = decode_image(path.read_bytes())
        if decoded.rgb.shape[1] > 640 or decoded.rgb.shape[0] > 480:
            raise ValueError("Video output dimensions exceeded")
        rows.append(
            {
                "sample_index": index,
                "pts_ms": index * 200,
                "relative_path": path.name,
                "pixel_sha256": decoded.pixel_sha256,
            }
        )
    if not rows or len(rows) > 18000 or file_sha256(source) != original_hash:
        raise ValueError("Video output empty, excessive, or source changed")
    frames = output / "frames.jsonl"
    frames.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
    manifest = {
        "schema_version": 1,
        "source_sha256": original_hash,
        "duration_ms": duration * 1000,
        "source_start_pts_ms": float(streams[0].get("start_time", 0)) * 1000,
        "pts_origin": "normalized_source_start",
        "fps": 5,
        "width_limit": 640,
        "height_limit": 480,
        "audio": False,
        "upright": True,
        "frames_sha256": file_sha256(frames),
        "samples": len(rows),
    }
    (output / "source-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    return frames
