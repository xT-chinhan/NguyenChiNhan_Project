import asyncio
import base64
import io
import json
import os
import socket
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

import httpx
import pytest
from PIL import Image
from websockets.asyncio.client import connect
from websockets.exceptions import InvalidStatus

from tests.integration.test_catalog_api import image_bytes
from tests.integration.test_runtime_postgres import published_route, token

BACKEND = Path(__file__).resolve().parents[2]


@contextmanager
def server(settings, tmp_path):
    with socket.socket() as address:
        address.bind(("127.0.0.1", 0))
        port = address.getsockname()[1]
    env = dict(
        os.environ,
        NAV_DB_URL=settings.db_url,
        NAV_ADMIN_TOKEN=settings.admin_token,
        NAV_MODEL_DIR=str(settings.model_dir),
        NAV_LOG_LEVEL="INFO",
        NAV_ENV="test",
        PYTHONPATH=f"{BACKEND}:{BACKEND / 'src'}",
    )
    log_path = tmp_path / "server.log"
    with log_path.open("w") as output:
        process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "tests.network_app:app",
                "--host",
                "127.0.0.1",
                "--port",
                str(port),
                "--workers",
                "1",
                "--ws-max-size",
                "1100000",
            ],
            cwd=BACKEND,
            env=env,
            stdout=output,
            stderr=output,
        )
        url = f"http://127.0.0.1:{port}"
        try:
            for _ in range(200):
                if process.poll() is not None:
                    raise AssertionError("Network adapter process exited during startup")
                try:
                    if httpx.get(url + "/health/ready", timeout=0.2).status_code == 200:
                        break
                except httpx.HTTPError:
                    pass
                time.sleep(0.025)
            else:
                raise AssertionError("Network adapter readiness timed out")
            yield url
        finally:
            process.terminate()
            try:
                process.wait(12)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    assert settings.admin_token not in log_path.read_text()
    assert "image_b64" not in log_path.read_text()


async def receive(ws, kind):
    while True:
        result = json.loads(await asyncio.wait_for(ws.recv(), 3))
        if result["type"] == kind:
            return result


def test_independent_ws_client_real_http_auth_and_postgres_snapshot(
    vision_client, engine, settings, tmp_path, admin_headers
):
    route = published_route(vision_client, admin_headers)
    _, headers = token(engine, tmp_path, "network-owner")
    _, outsider = token(engine, tmp_path, "network-outsider")
    with server(settings, tmp_path) as url:
        response = httpx.post(
            url + "/v1/sessions",
            headers=headers,
            json={"route_id": route["id"], "sensor": {"mode": "rgb"}, "language": "vi-VN"},
        )
        assert response.status_code == 201
        path = response.json()["stream_path"]

        async def exchange():
            ws_url = url.replace("http:", "ws:") + path
            with pytest.raises(InvalidStatus) as denied:
                async with connect(ws_url, additional_headers=outsider, proxy=None):
                    pass
            assert denied.value.response.status_code == 403
            async with connect(ws_url, additional_headers=headers, proxy=None) as ws:
                assert (await receive(ws, "welcome"))["protocol_version"] == 1
                for index in range(3):
                    request = await receive(ws, "capture_request")
                    stream = io.BytesIO()
                    Image.open(io.BytesIO(image_bytes(0, index))).convert("RGB").save(
                        stream, "JPEG"
                    )
                    capture = time.monotonic_ns() // 1_000_000
                    await ws.send(
                        json.dumps(
                            {
                                "type": "frame",
                                "seq": request["seq"],
                                "frame_token": request["frame_token"],
                                "capture_monotonic_ms": capture,
                                "image_b64": base64.b64encode(stream.getvalue()).decode(),
                            }
                        )
                    )
                    result = await receive(ws, "frame_result")
                    assert time.monotonic_ns() // 1_000_000 - capture < 1000
                assert result["last_confirmed_seq"] == 0
                assert result["instruction"]["code"] == "CONTINUE_STRAIGHT"
                await ws.send(json.dumps({"type": "control", "command": "pause"}))
                assert (await receive(ws, "control_result"))["state"] == "paused"

        asyncio.run(exchange())
        assert (
            httpx.delete(url + f"/v1/sessions/{response.json()['id']}", headers=headers).status_code
            == 204
        )
    secret = headers["Authorization"].removeprefix("Bearer ")
    assert secret not in (tmp_path / "server.log").read_text()
