import json
from pathlib import Path
from uuid import UUID

import httpx
import pytest
from PIL import Image

from navcore.cli.bundle import confined_file, load_bundle, read_json
from navcore.cli.route_import import (
    client_configuration,
    import_route,
    register_clients,
)


def make_bundle(root: Path, count: int = 4) -> Path:
    checkpoints = []
    for seq in range(count):
        images = []
        for image_index in range(3):
            relative = f"references/cp{seq}/{image_index}.png"
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            Image.new(
                "RGB",
                (32, 32),
                (seq * 40 + image_index * 5, image_index * 30, seq * 20),
            ).save(path)
            images.append(relative)
        checkpoints.append(
            {
                "seq": seq,
                "depart_action": "arrive"
                if seq == count - 1
                else ["straight", "left", "right"][seq % 3],
                "landmark": f"Checkpoint {seq}",
                "heading_deg": None,
                "source_group": "reference-walk",
                "images": images,
            }
        )
    value = {
        "schema_version": 1,
        "map": {"name": "Map"},
        "from_place": {"name": "From"},
        "to_place": {"name": "To"},
        "route": {"name": "Route"},
        "checkpoints": checkpoints,
    }
    path = root / "bundle.json"
    path.write_text(json.dumps(value))
    return path


def test_bundle_strict_and_distinct(tmp_path):
    path = make_bundle(tmp_path)
    bundle = load_bundle(path)
    assert len(bundle.pixel_hashes) == 4
    assert len({p for group in bundle.pixel_hashes for p in group}) == 12
    raw = json.loads(path.read_text())
    raw["checkpoints"][1]["images"][0] = raw["checkpoints"][0]["images"][0]
    path.write_text(json.dumps(raw))
    with pytest.raises(ValueError, match="Duplicate reference"):
        load_bundle(path)


@pytest.mark.parametrize(
    "relative", ["../escape.jpg", "/etc/passwd", "a/../b.jpg", "./b.jpg", "a\\b.jpg"]
)
def test_confined_paths_reject_traversal(tmp_path, relative):
    with pytest.raises(ValueError):
        confined_file(tmp_path, relative)


def test_symlink_and_unknown_fields_are_rejected(tmp_path):
    path = make_bundle(tmp_path)
    (tmp_path / "link").symlink_to(tmp_path / "references", target_is_directory=True)
    with pytest.raises(ValueError, match="symlink"):
        confined_file(tmp_path, "link/cp0/0.png")
    raw = json.loads(path.read_text())
    raw["token"] = "never allowed"
    path.write_text(json.dumps(raw))
    with pytest.raises(ValueError):
        load_bundle(path)
    path.write_text('{"schema_version":1,"schema_version":1}')
    with pytest.raises(ValueError, match="Duplicate JSON"):
        read_json(path)


def test_import_failure_keeps_draft_receipt_and_never_publishes(tmp_path):
    path = make_bundle(tmp_path)
    requests = []

    def handler(request):
        requests.append(request)
        if request.url.path.endswith("checkpoints"):
            return httpx.Response(422, json={"error": "invalid reference"})
        return httpx.Response(201, json={"id": str(UUID(int=len(requests)))})

    receipt = tmp_path / "receipt.json"
    with (
        httpx.Client(
            base_url="http://unit.invalid", transport=httpx.MockTransport(handler)
        ) as client,
        pytest.raises(httpx.HTTPStatusError),
    ):
        import_route(path, receipt, client)
    saved = json.loads(receipt.read_text())
    assert saved["status"] == "failed"
    assert saved["route_status"] == "draft"
    assert saved["resources"]["route_id"] == str(UUID(int=4))
    assert not any(r.url.path.endswith("publish") for r in requests)
    assert requests[-1].headers["content-type"].startswith("multipart/form-data")


def test_client_requires_only_role_env_and_no_token_argument(monkeypatch):
    import argparse

    monkeypatch.setenv("NAV_DEVICE_TOKEN", "private-device-value")
    monkeypatch.delenv("NAV_DB_URL", raising=False)
    monkeypatch.delenv("NAV_ADMIN_TOKEN", raising=False)
    assert client_configuration("device") == (
        "http://127.0.0.1:8095",
        "private-device-value",
    )
    parser = argparse.ArgumentParser()
    register_clients(parser.add_subparsers(dest="command"))
    with pytest.raises(SystemExit):
        parser.parse_args(["replay", "--token", "unsafe"])
