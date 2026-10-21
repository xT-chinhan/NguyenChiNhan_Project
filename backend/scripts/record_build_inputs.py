"""Record an allowlisted source snapshot without reading private configuration."""

import argparse
import importlib.metadata
import json
import platform
from pathlib import Path


def collect(root: Path) -> dict:
    root = root.resolve()
    from navcore.cli._benchmark_inputs import build_input_identity

    return {
        "python": platform.python_version(),
        "platform": platform.platform(),
        "packages": sorted(
            f"{d.metadata['Name']}=={d.version}" for d in importlib.metadata.distributions()
        ),
        **build_input_identity(root, root / "models"),
        "adapter_kind": "unverified",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(collect(args.backend), indent=2) + "\n")
