"""Deterministic local input identities; never reads process environment."""

from pathlib import Path

from navcore.cli._benchmark_inputs import build_input_identity


def local_inputs() -> dict:
    backend = Path(__file__).resolve().parents[3]
    inputs = build_input_identity(backend, backend / "models")
    inputs.pop("source_files_sha256")
    return inputs
