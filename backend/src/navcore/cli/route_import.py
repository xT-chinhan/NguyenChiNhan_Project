"""REST-only route importer and client command registration."""

import argparse
import asyncio
import json
import os
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

import httpx
from websockets.exceptions import WebSocketException

from navcore.cli.bundle import load_bundle


def client_configuration(role: str) -> tuple[str, str]:
    url = os.environ.get("NAV_API_URL", "http://127.0.0.1:8095").rstrip("/")
    parsed = urlsplit(url)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
    ):
        raise ValueError("NAV_API_URL must be an HTTP origin without credentials")
    token = os.environ.get("NAV_" + role.upper() + "_TOKEN", "")
    if not token or any(c.isspace() for c in token):
        raise ValueError("Required client token environment variable is missing or invalid")
    return url, token


def import_route(bundle_path: Path, receipt_path: Path, client: httpx.Client) -> dict:
    bundle = load_bundle(bundle_path)
    receipt = {
        "schema_version": 1,
        "status": "importing",
        "resources": {},
        "checkpoints_uploaded": 0,
    }
    if receipt_path.exists() or receipt_path.is_symlink():
        raise ValueError("Receipt already exists; choose a new receipt path")
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    with receipt_path.open("x", encoding="utf-8"):
        pass

    def save():
        with tempfile.NamedTemporaryFile(
            mode="w", dir=receipt_path.parent, delete=False, encoding="utf-8"
        ) as stream:
            temporary = Path(stream.name)
            try:
                stream.write(json.dumps(receipt, indent=2) + "\n")
                stream.flush()
                os.fsync(stream.fileno())
            except BaseException:
                temporary.unlink(missing_ok=True)
                raise
        try:
            os.replace(temporary, receipt_path)
        finally:
            temporary.unlink(missing_ok=True)

    def post(path, **kwargs):
        response = client.post(path, **kwargs)
        response.raise_for_status()
        value = response.json()
        UUID(value["id"])
        return value

    save()
    try:
        map_id = post("/v1/admin/maps", json=bundle.data.map.model_dump())["id"]
        receipt["resources"]["map_id"] = map_id
        save()
        for key in ("from_place", "to_place"):
            place = post(
                f"/v1/admin/maps/{map_id}/places",
                json=getattr(bundle.data, key).model_dump(),
            )
            receipt["resources"][key + "_id"] = place["id"]
            save()
        route = post(
            "/v1/admin/routes",
            json={
                "map_id": map_id,
                "name": bundle.data.route.name,
                "from_place_id": receipt["resources"]["from_place_id"],
                "to_place_id": receipt["resources"]["to_place_id"],
            },
        )
        route_id = route["id"]
        receipt["resources"]["route_id"] = route_id
        receipt["route_status"] = "draft"
        save()
        for checkpoint, images in zip(bundle.data.checkpoints, bundle.images, strict=True):
            metadata = checkpoint.model_dump(mode="json", exclude={"images"})
            files = [
                (
                    "images",
                    (
                        image.name,
                        image.read_bytes(),
                        "image/png" if image.suffix.lower() == ".png" else "image/jpeg",
                    ),
                )
                for image in images
            ]
            post(
                f"/v1/admin/routes/{route_id}/checkpoints",
                data={"metadata": json.dumps(metadata)},
                files=files,
            )
            receipt["checkpoints_uploaded"] += 1
            save()
        post(f"/v1/admin/routes/{route_id}/publish", json={})
        receipt.update(status="complete", route_status="published")
        save()
    except Exception:
        receipt["status"] = "failed"
        receipt["error"] = "IMPORT_FAILED"
        save()
        raise
    return receipt


def register_clients(commands: argparse._SubParsersAction) -> None:
    imp = commands.add_parser(
        "route-import", help="Validate and import an explicit local route bundle"
    )
    imp.add_argument("--bundle", type=Path, required=True)
    imp.add_argument("--receipt", type=Path)
    video = commands.add_parser("prepare-video", help="Prepare upright 5 fps replay samples")
    video.add_argument("--input", type=Path, required=True)
    video.add_argument("--output-dir", type=Path, required=True)
    replay = commands.add_parser("replay", help="Replay RGB samples at 1x through an owned session")
    replay.add_argument("--route-id", type=UUID, required=True)
    replay.add_argument("--frames", type=Path, required=True)
    replay.add_argument("--output", type=Path, required=True)
    replay.add_argument("--clip-id")
    evaluate = commands.add_parser("evaluate", help="Evaluate independently labelled pilot traces")
    evaluate.add_argument("--trace", type=Path, action="append", default=[])
    evaluate.add_argument("--ground-truth", type=Path, required=True)
    evaluate.add_argument("--dataset-manifest", type=Path)
    evaluate.add_argument("--bundle", type=Path)
    evaluate.add_argument("--report-dir", type=Path, required=True)
    evaluate.add_argument("--server-receipt", type=Path)


def run_clients(args: argparse.Namespace) -> int:
    try:
        if args.command == "route-import":
            url, token = client_configuration("admin")
            receipt = args.receipt or args.bundle.parent / "import-receipt.json"
            with httpx.Client(
                base_url=url,
                headers={"Authorization": f"Bearer {token}"},
                timeout=30,
                follow_redirects=False,
                trust_env=False,
            ) as client:
                result = import_route(args.bundle, receipt, client)
            print(json.dumps(result))
            return 0
        if args.command == "prepare-video":
            from navcore.cli.video import prepare_video

            print(prepare_video(args.input, args.output_dir))
            return 0
        if args.command == "replay":
            from navcore.cli.replay import replay_session

            url, token = client_configuration("device")
            asyncio.run(
                replay_session(
                    url,
                    token,
                    str(args.route_id),
                    args.frames,
                    args.output,
                    args.clip_id,
                )
            )
            return 0
        if args.command == "evaluate":
            from navcore.cli.evaluate import evaluate

            return evaluate(args)
    except (
        ValueError,
        OSError,
        httpx.HTTPError,
        WebSocketException,
        subprocess.SubprocessError,
        KeyError,
    ):
        # Error payloads may contain credentials; only expose a stable local code.
        print(json.dumps({"error": "CLIENT_COMMAND_FAILED"}))
        return 1
    return 1
