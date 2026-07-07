from __future__ import annotations

import argparse
import json
from pathlib import Path

from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Model

from src.azure_auth import get_ml_client, get_registry_client
from src.config import load_env_config


def register_model(env_name: str, model_path: str, model_name: str, evaluation_path: str) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)
    registry_client = get_registry_client(config)

    evaluation = json.loads(Path(evaluation_path).read_text())
    if not evaluation.get("approved", False):
        raise ValueError("Model not approved by evaluation gate.")

    model = Model(
        name=model_name,
        path=model_path,
        type=AssetTypes.CUSTOM_MODEL,
        description="Used car price model approved in workspace and promoted to registry.",
        tags={
            **config["tags"],
            "rmse": str(evaluation["metrics"]["rmse"]),
            "r2": str(evaluation["metrics"]["r2"]),
        },
    )

    created = ml_client.models.create_or_update(model)
    print(f"Workspace model version: {created.version}")

    promoted = registry_client.models.create_or_update(
        Model(
            name=model_name,
            path=f"azureml:{model_name}:{created.version}",
            type=AssetTypes.CUSTOM_MODEL,
            description=model.description,
            tags={
                **model.tags,
                "workspace_model_version": str(created.version),
                "source_workspace": config["workspace_name"],
            },
        )
    )
    print(f"Registry model version: {promoted.version}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--model-path", required=True)
    parser.add_argument("--model-name", default="used-car-price-model")
    parser.add_argument("--evaluation-path", required=True)
    args = parser.parse_args()
    register_model(args.env, args.model_path, args.model_name, args.evaluation_path)


if __name__ == "__main__":
    main()
