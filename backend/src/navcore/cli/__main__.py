import argparse
import json
import os
from pathlib import Path
from uuid import UUID


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m navcore.cli")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("bootstrap-dev", help="Create local private configuration")
    from navcore.cli.benchmark import register_benchmark
    from navcore.cli.models import register_models
    from navcore.cli.route_import import register_clients

    register_models(commands)
    register_clients(commands)
    register_benchmark(commands)
    create = commands.add_parser("device-create", help="Create private device token file")
    create.add_argument("--name", required=True)
    create.add_argument("--output-env", type=Path, required=True)
    revoke = commands.add_parser("device-revoke")
    revoke.add_argument("--id", type=UUID, required=True)
    args = parser.parse_args()
    if args.command == "bootstrap-dev":
        from navcore.cli.bootstrap import bootstrap

        print(bootstrap())
    elif args.command in {"models-fetch", "models-verify"}:
        from navcore.cli.models import run_models

        run_models(args)
    elif args.command in {"route-import", "prepare-video", "replay", "evaluate"}:
        from navcore.cli.route_import import run_clients

        raise SystemExit(run_clients(args))
    elif args.command == "benchmark":
        from navcore.cli.benchmark import run_benchmark

        raise SystemExit(run_benchmark(args))
    elif args.command in {"device-create", "device-revoke"}:
        from navcore.cli.devices import create_device, revoke_device
        from navcore.storage.database import make_engine

        db_url = os.environ.get("NAV_DB_URL")
        if not db_url:
            parser.error("NAV_DB_URL is required")
        engine = make_engine(db_url)
        try:
            if args.command == "device-create":
                result = create_device(
                    engine,
                    args.name,
                    args.output_env,
                    os.environ.get("NAV_API_URL", "http://127.0.0.1:8095"),
                )
            else:
                result = {"id": str(args.id), "revoked": revoke_device(engine, args.id)}
            print(json.dumps(result))
        finally:
            engine.dispose()


if __name__ == "__main__":
    main()
