from __future__ import annotations

import argparse
from pathlib import Path

from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Data
from azure.core.exceptions import ResourceNotFoundError

from src.azure_auth import get_ml_client
from src.config import load_env_config


def register_data_asset(env_name: str, csv_path: str, name: str, version: str) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)

    try:
        existing = ml_client.data.get(name=name, version=version)
        print(f"Data asset already registered: {existing.name}:{existing.version}")
        return
    except ResourceNotFoundError:
        pass

    csv_file = Path(csv_path)
    if not csv_file.exists():
        raise FileNotFoundError(f"Training data file not found: {csv_file}")

    created = ml_client.data.create_or_update(
        Data(
            name=name,
            version=version,
            path=str(csv_file),
            type=AssetTypes.URI_FILE,
            description="Used car training reference data.",
            tags=config["tags"],
        )
    )
    print(f"Registered data asset {created.name}:{created.version}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--csv", required=True)
    parser.add_argument("--name", default="used-car-training-reference")
    parser.add_argument("--version", default="1")
    args = parser.parse_args()
    register_data_asset(args.env, args.csv, args.name, args.version)


if __name__ == "__main__":
    main()
