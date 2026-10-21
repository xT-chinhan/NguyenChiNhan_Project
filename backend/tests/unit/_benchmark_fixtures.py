"""Small external HTTP/WS doubles; metric and protocol logic remain real."""

import json
import os
import sys
from pathlib import Path

import httpx

from navcore.cli._benchmark_metrics import performance_decision


def acceptance_decision(summary, **overrides):
    values = dict(
        sessions=1,
        warmup=30,
        duration=300,
        completed=True,
        attested=True,
        real_models=True,
        standard_frames=True,
    )
    return performance_decision(summary, **{**values, **overrides})


def check_script_environment(root):
    scripts = root / "scripts"
    scripts.mkdir()
    source = Path(__file__).parents[2] / "scripts" / "check.sh"
    script = scripts / "check.sh"
    script.write_bytes(source.read_bytes())
    executable, log = root / "python", root / "calls.jsonl"
    executable.write_text(
        f"#!{sys.executable}\n"
        "import json, os, subprocess, sys\n"
        "if sys.argv[1] == '-c':\n"
        f"    result = subprocess.run([{sys.executable!r}, *sys.argv[1:]], check=False)\n"
        "    sys.exit(result.returncode)\n"
        "with open(os.environ['CALL_LOG'], 'a') as stream:\n"
        "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
    )
    executable.chmod(0o700)
    environment = {**os.environ, "NAV_CHECK_PYTHON": str(executable), "CALL_LOG": str(log)}
    return script, log, environment


def result_payload(**timing):
    return {
        "timing": {
            "decode_ms": 2,
            "queue_ms": 3,
            "inference_ms": 100,
            "core_ms": 1,
            "request_to_result_ms": 150,
            **timing,
        }
    }


def write_device(root: Path, name="one.env", token="navdev_" + "a" * 43):
    path = root / name
    path.write_text(f"NAV_API_URL=http://127.0.0.1:8095\nNAV_DEVICE_TOKEN={token}\n")
    path.chmod(0o600)
    return path


class JPEGDataset:
    def jpeg(self, elapsed_ms):
        return b"prepared JPEG"


class AckDelayWire:
    def __init__(self, clock, session_id, token):
        self.clock, self.token = clock, token
        self.sent = []
        self.incoming = [
            {
                "type": "welcome",
                "protocol_version": 1,
                "session_id": session_id,
                "mode": "rgb",
                "max_result_age_ms": 1000,
            },
            {"type": "capture_request", "seq": 1, "frame_token": token, "deadline_ms": 1000},
        ]

    async def recv(self):
        message = self.incoming.pop(0)
        if message["type"] == "frame_result":
            self.clock[0] += 0.1
        return json.dumps(message)

    async def send(self, raw):
        message = json.loads(raw)
        self.sent.append(message)
        if message["type"] == "frame":
            assert message["frame_token"] == self.token
            assert message["seq"] == 1
            assert message["capture_monotonic_ms"] >= 30000
            self.incoming.append(
                {
                    "type": "frame_result",
                    "seq": 1,
                    "capture_monotonic_ms": message["capture_monotonic_ms"],
                    "movement_held": False,
                    **result_payload(event_loop_lag_ms=1),
                    "instruction": {
                        "id": "33333333-3333-4333-8333-333333333333",
                        "frame_seq": 1,
                        "capture_monotonic_ms": message["capture_monotonic_ms"],
                        "valid_for_ms": 100,
                        "priority": "guidance",
                        "code": "TURN_LEFT",
                    },
                }
            )
        elif message["stage"] == "received":
            self.clock[0] += 0.5


class AdmissionFailureHTTP:
    def __init__(self, created):
        self.created, self.deleted, self.posts = created, [], 0

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass

    async def post(self, *args, **kwargs):
        self.posts += 1
        if self.posts == 1:
            return httpx.Response(
                201,
                json={
                    "id": self.created,
                    "stream_path": f"/v1/sessions/{self.created}/stream",
                    "checkpoint_count": 4,
                },
            )
        return httpx.Response(503, json={"error": {"code": "SESSION_CAPACITY"}})

    async def delete(self, path, **kwargs):
        self.deleted.append(path)
        return httpx.Response(204)
