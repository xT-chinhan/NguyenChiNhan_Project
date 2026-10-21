"""Independent annotation schemas and byte/pixel/capture-group split checks."""

from pathlib import Path
from typing import Annotated, Literal

from pydantic import Field, StrictBool, StrictInt, model_validator

from navcore.cli.bundle import RouteBundle, confined_file, file_sha256, read_json
from navcore.schemas.catalog import Contract

Hash = Annotated[str, Field(pattern=r"^[0-9a-f]{64}$", strict=True)]
Label = Annotated[str, Field(min_length=1, max_length=120, strict=True)]
Time = Annotated[float, Field(ge=0, strict=True)]
Box = tuple[float, float, float, float]


class DatasetFile(Contract):
    path: Label
    sha256: Hash
    source: Literal["reference", "query"]
    split: Literal["reference", "dev", "test"]
    capture_group: Label
    pixel_sha256: Annotated[list[Hash], Field(max_length=18000)]
    duration_ms: Time | None = None


class DatasetManifest(Contract):
    schema_version: Literal[1]
    dataset_id: Label
    created_at: Label
    files: Annotated[list[DatasetFile], Field(min_length=1, max_length=1000)]
    capture_groups: list[Label] = Field(default_factory=list)
    capture_conditions: dict[Label, Annotated[str, Field(max_length=500)]] = Field(
        default_factory=dict
    )
    limitations: list[Annotated[str, Field(max_length=500)]] = Field(default_factory=list)


class CheckpointLabel(Contract):
    seq: Annotated[StrictInt, Field(ge=0, le=63)]
    visible_start_ms: Time
    visible_end_ms: Time
    expected_code: Literal["CONTINUE_STRAIGHT", "TURN_LEFT", "TURN_RIGHT", "ARRIVED"]

    @model_validator(mode="after")
    def ordered(self):
        if self.visible_end_ms < self.visible_start_ms:
            raise ValueError("Invalid annotation window")
        return self


class ObjectLabel(Contract):
    class_name: Literal["person", "chair"]
    bbox: Box
    rgb_notice_expected: StrictBool

    @model_validator(mode="after")
    def valid_box(self):
        x1, y1, x2, y2 = self.bbox
        if not (0 <= x1 < x2 <= 640 and 0 <= y1 < y2 <= 480):
            raise ValueError("Invalid upright annotation bbox")
        return self


class TimedObject(ObjectLabel):
    pts_ms: Time


class PerceptionFrame(Contract):
    pts_ms: Time
    objects: Annotated[list[ObjectLabel], Field(max_length=100)]


class ForbiddenInterval(Contract):
    start_ms: Time
    end_ms: Time
    codes: list[Literal["CONTINUE_STRAIGHT", "TURN_LEFT", "TURN_RIGHT", "ARRIVED"]]
    reason: Label

    @model_validator(mode="after")
    def ordered(self):
        if self.end_ms < self.start_ms:
            raise ValueError("Invalid forbidden interval")
        return self


class ClipLabel(Contract):
    clip_id: Label
    file: Label
    split: Literal["dev", "test"]
    capture_group: Label
    expected_completion: StrictBool
    checkpoints: Annotated[list[CheckpointLabel], Field(max_length=64)]
    objects: Annotated[list[TimedObject], Field(max_length=18000)] = Field(default_factory=list)
    perception_frames: Annotated[list[PerceptionFrame], Field(max_length=18000)] = Field(
        default_factory=list
    )
    forbidden_intervals: list[ForbiddenInterval] = Field(default_factory=list)
    allowed_confirmed_seqs: list[Annotated[StrictInt, Field(ge=0, le=63)]] = Field(
        default_factory=list
    )

    @model_validator(mode="after")
    def distinct_observations(self):
        times = [frame.pts_ms for frame in self.perception_frames]
        if len(times) != len(set(times)):
            raise ValueError("Perception frame timestamps must be unique within a clip")
        return self


class AnnotationProvenance(Contract):
    kind: Literal["human"]
    independent_of_model: Literal[True]


class GroundTruth(Contract):
    schema_version: Literal[1]
    annotation_provenance: AnnotationProvenance | None = None
    clips: Annotated[list[ClipLabel], Field(min_length=1, max_length=100)]


def validate_dataset(
    root: Path, manifest_path: Path, truth_path: Path, bundle: RouteBundle
) -> tuple[DatasetManifest, GroundTruth, list[str]]:
    if (
        manifest_path.parent.resolve() != root.resolve()
        or truth_path.parent.resolve() != root.resolve()
    ):
        raise ValueError("Manifest and ground truth must be in bundle root")
    manifest = DatasetManifest.model_validate(read_json(manifest_path))
    truth = GroundTruth.model_validate(read_json(truth_path))
    files, hashes, pixels, groups = {}, {}, {}, {}
    missing = []
    for row in manifest.files:
        if row.path in files:
            raise ValueError("Duplicate dataset path")
        files[row.path] = row
        path = confined_file(root, row.path)
        if file_sha256(path) != row.sha256:
            raise ValueError("Dataset file hash mismatch")
        if (row.source == "reference") != (row.split == "reference"):
            raise ValueError("Invalid source/split pairing")
        group_role = (row.source, row.split)
        if row.capture_group in groups and groups[row.capture_group] != group_role:
            raise ValueError("Capture group split leakage")
        groups[row.capture_group] = group_role
        if row.sha256 in hashes and hashes[row.sha256] != (
            row.source,
            row.capture_group,
        ):
            raise ValueError("File-byte leakage")
        hashes[row.sha256] = (row.source, row.capture_group)
        for pixel in row.pixel_sha256:
            if pixel in pixels and pixels[pixel] != (row.source, row.capture_group):
                raise ValueError("Canonical pixel leakage")
            pixels[pixel] = (row.source, row.capture_group)
        if row.source == "query" and not row.pixel_sha256:
            missing.append("Query canonical frame hashes missing: " + row.path)
        if row.source == "query" and (row.duration_ms is None or row.duration_ms <= 0):
            missing.append("Query duration missing: " + row.path)
    for checkpoint, paths, actual_hashes in zip(
        bundle.data.checkpoints, bundle.images, bundle.pixel_hashes, strict=True
    ):
        for path, pixel in zip(paths, actual_hashes, strict=True):
            row = files.get(path.relative_to(root).as_posix())
            if (
                row is None
                or row.source != "reference"
                or row.capture_group != checkpoint.source_group
                or row.pixel_sha256 != [pixel]
            ):
                raise ValueError("Reference provenance does not match bundle")
    clip_ids, clip_paths = set(), set()
    for clip in truth.clips:
        if clip.clip_id in clip_ids or clip.file in clip_paths:
            raise ValueError("Duplicate annotation clip")
        clip_ids.add(clip.clip_id)
        clip_paths.add(clip.file)
        row = files.get(clip.file)
        if (
            row is None
            or row.source != "query"
            or row.split != clip.split
            or row.capture_group != clip.capture_group
        ):
            raise ValueError("Query annotation provenance mismatch")
        seqs = [label.seq for label in clip.checkpoints]
        if len(seqs) != len(set(seqs)):
            raise ValueError("Duplicate checkpoint annotation")
        if (
            clip.expected_completion
            and clip.split == "test"
            and seqs != list(range(len(bundle.data.checkpoints)))
        ):
            missing.append("Positive clip lacks every checkpoint label: " + clip.clip_id)
        for label in clip.checkpoints:
            expected = {
                "straight": "CONTINUE_STRAIGHT",
                "left": "TURN_LEFT",
                "right": "TURN_RIGHT",
                "arrive": "ARRIVED",
            }
            if (
                label.seq >= len(bundle.data.checkpoints)
                or label.expected_code != expected[bundle.data.checkpoints[label.seq].depart_action]
            ):
                raise ValueError("Checkpoint ground truth conflicts with route metadata")
    positive = [c for c in truth.clips if c.split == "test" and c.expected_completion]
    negative = [c for c in truth.clips if c.split == "test" and not c.expected_completion]
    if len(bundle.data.checkpoints) < 4 or sum(map(len, bundle.images)) < 12:
        missing.append("Pilot needs four checkpoints and twelve distinct references")
    if not any(c.split == "dev" for c in truth.clips):
        missing.append("Independent dev clip missing")
    if len({c.capture_group for c in positive}) < 2 or len({c.capture_group for c in negative}) < 2:
        missing.append("Two independent positive and two negative test clips required")
    if truth.annotation_provenance is None:
        missing.append("Human annotation independence attestation missing")
    frames = [
        frame for clip in truth.clips if clip.split == "test" for frame in clip.perception_frames
    ]
    if sum(bool(f.objects) for f in frames) < 30 or sum(not f.objects for f in frames) < 30:
        missing.append("Perception needs thirty labelled object frames and thirty clear frames")
    return manifest, truth, missing
