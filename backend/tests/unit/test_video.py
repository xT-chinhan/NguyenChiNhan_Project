import json
from pathlib import Path

import pytest
from PIL import Image

from navcore.cli.bundle import file_sha256
from navcore.cli.video import load_frames, prepare_video
from navcore.vision.images import decode_image


def prepared_frames(root: Path, count=3) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    rows = []
    for index in range(count):
        path = root / f"frame-{index:06d}.jpg"
        Image.new("RGB", (64, 48), (index * 50, 70, 100)).save(path)
        rows.append(
            {
                "sample_index": index,
                "pts_ms": index * 200,
                "relative_path": path.name,
                "pixel_sha256": decode_image(path.read_bytes()).pixel_sha256,
            }
        )
    path = root / "frames.jsonl"
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))
    (root / "source-manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "fps": 5,
                "source_sha256": "c" * 64,
                "frames_sha256": file_sha256(path),
                "duration_ms": count * 200,
            }
        )
    )
    return path


def test_playback_uses_current_clock_and_skips_backlog(tmp_path):
    frames = load_frames(prepared_frames(tmp_path))
    assert frames.choose(399).sample_index == 1
    assert frames.choose(400, 0).sample_index == 2
    assert frames.choose(400, 2) is None
    assert frames.decode(frames.samples[1]).startswith(b"\xff\xd8")
    (tmp_path / frames.samples[1].relative_path).write_bytes(
        (tmp_path / frames.samples[0].relative_path).read_bytes()
    )
    with pytest.raises(ValueError, match="pixels changed"):
        frames.decode(frames.samples[1])


def test_manifest_tampering_is_rejected(tmp_path):
    path = prepared_frames(tmp_path)
    path.write_text(path.read_text() + "\n")
    with pytest.raises(ValueError, match="source manifest"):
        load_frames(path)


def test_prepare_refuses_nonempty_and_uses_argv_without_shell(tmp_path, monkeypatch):
    source = tmp_path / "source.mp4"
    source.write_bytes(b"source remains unchanged")
    output = tmp_path / "frames"
    calls = []

    def fake_run(argv, **kwargs):
        import subprocess

        calls.append((argv, kwargs))
        if argv[0] == "ffprobe":
            return subprocess.CompletedProcess(
                argv,
                0,
                json.dumps({"streams": [{"duration": "0.4", "start_time": "2.0"}]}).encode(),
                b"",
            )
        for index in range(2):
            Image.new("RGB", (64, 48), (50 * index, 80, 90)).save(output / f"frame-{index:06d}.jpg")
        return subprocess.CompletedProcess(argv, 0, b"", b"")

    monkeypatch.setattr("navcore.cli.video.subprocess.run", fake_run)
    before = file_sha256(source)
    path = prepare_video(source, output)
    assert file_sha256(source) == before
    assert len(load_frames(path).samples) == 2
    assert all(call[1]["shell"] is False for call in calls)
    command = calls[1][0]
    assert "-an" in command and "fps=5" in command[command.index("-vf") + 1]
    assert "-n" in command
    with pytest.raises(ValueError, match="must be empty"):
        prepare_video(source, output)
