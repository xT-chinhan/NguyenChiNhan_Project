import importlib.util
import os
from pathlib import Path

import pytest

from navcore.cli._benchmark_inputs import build_input_identity, process_identity, source_identity
from navcore.cli.evidence import local_inputs

BACKEND = Path(__file__).resolve().parents[2]


def test_all_report_tools_share_allowlisted_identity_without_reading_private_env(tmp_path):
    (tmp_path / "src").mkdir()
    source = tmp_path / "src" / "app.py"
    source.write_text("print('application')\n")
    (tmp_path / "config").mkdir()
    private = tmp_path / "config" / ".env"
    private.write_text("NAV_ADMIN_TOKEN=private-never-read")
    first = source_identity(tmp_path)
    private.write_text("NAV_ADMIN_TOKEN=rotated-never-read")
    assert source_identity(tmp_path) == first
    source.write_text("print('changed')\n")
    assert source_identity(tmp_path) != first
    inputs = build_input_identity(BACKEND, BACKEND / "models")
    assert local_inputs()["source_sha256"] == inputs["source_sha256"]
    assert not any(path.endswith(".env") for path in inputs["source_files_sha256"])


def test_server_receipt_refuses_non_server_process_even_with_verified_artifacts(monkeypatch):
    from types import SimpleNamespace

    source = BACKEND / "scripts" / "record_server_receipt.py"
    spec = importlib.util.spec_from_file_location("test_server_receipt", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(
        module, "verify_artifacts", lambda _: SimpleNamespace(encoder_fingerprint="a" * 64)
    )
    with pytest.raises(ValueError, match="not the navigation"):
        module.receipt(
            BACKEND, BACKEND / "models", "http://127.0.0.1:8095", os.getpid(), "cpu", [], None
        )
    assert process_identity(os.getpid())["pid"] == os.getpid()
