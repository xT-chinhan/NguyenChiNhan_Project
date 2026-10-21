"""Strict, bounded local bundle validation before any REST mutation."""

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Annotated, Literal

from pydantic import Field

from navcore.schemas.catalog import CheckpointMetadata, Contract, Named
from navcore.vision.images import MAX_IMAGE_BYTES, decode_image


def confined_file(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative:
        raise ValueError("Invalid relative dataset path")
    parts = PurePosixPath(relative)
    if parts.is_absolute() or any(p in {".", ".."} for p in relative.split("/")):
        raise ValueError("Dataset paths must stay inside bundle root")
    current = root
    for part in parts.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("Dataset symlinks are forbidden")
    if not current.is_file() or not current.resolve().is_relative_to(root.resolve()):
        raise ValueError("Dataset file is missing or outside bundle root")
    return current


def read_json(path: Path, maximum: int = 4 * 1024 * 1024) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise ValueError("Missing or oversized JSON file")
    with path.open("rb") as stream:
        data = stream.read(maximum + 1)
    if len(data) > maximum:
        raise ValueError("Oversized JSON file")

    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = value
        return result

    value = json.loads(
        data,
        object_pairs_hook=unique,
        parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON")),
    )
    if not isinstance(value, dict):
        raise ValueError("JSON object required")  # noqa: TRY004 - untrusted JSON validation
    return value


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class BundleCheckpoint(CheckpointMetadata):
    images: Annotated[list[str], Field(min_length=3, max_length=8)]


class BundleSchema(Contract):
    schema_version: Literal[1]
    map: Named
    from_place: Named
    to_place: Named
    route: Named
    checkpoints: Annotated[list[BundleCheckpoint], Field(min_length=2, max_length=64)]


@dataclass(frozen=True)
class RouteBundle:
    path: Path
    data: BundleSchema
    images: tuple[tuple[Path, ...], ...]
    pixel_hashes: tuple[tuple[str, ...], ...]


def load_bundle(path: Path) -> RouteBundle:
    if path.is_symlink():
        raise ValueError("Bundle symlinks are forbidden")
    path = path.absolute()
    root = path.parent
    # Reject symlink ancestors too, before resolve erases their identity.
    if any(parent.is_symlink() for parent in (root, *root.parents)):
        raise ValueError("Bundle ancestors must not be symlinks")
    data = BundleSchema.model_validate(read_json(path))
    if data.from_place.name.casefold() == data.to_place.name.casefold():
        raise ValueError("Route endpoints must differ")
    images, hashes, seen, total = [], [], set(), 0
    for seq, checkpoint in enumerate(data.checkpoints):
        if checkpoint.seq != seq or (checkpoint.depart_action == "arrive") != (
            seq == len(data.checkpoints) - 1
        ):
            raise ValueError("Checkpoint sequence/actions are invalid")
        paths, pixels = [], []
        for relative in checkpoint.images:
            image = confined_file(root, relative)
            size = image.stat().st_size
            if not 0 < size <= MAX_IMAGE_BYTES:
                raise ValueError("Reference image byte limit exceeded")
            total += size
            if total > 64 * 1024 * 1024:
                raise ValueError("Route image byte limit exceeded")
            pixel = decode_image(image.read_bytes(), admin=True).pixel_sha256
            if pixel in seen:
                raise ValueError("Duplicate reference pixels")
            seen.add(pixel)
            paths.append(image)
            pixels.append(pixel)
        images.append(tuple(paths))
        hashes.append(tuple(pixels))
    return RouteBundle(path, data, tuple(images), tuple(hashes))
