from __future__ import annotations

import argparse

from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Model

from src.azure_auth import get_ml_client, get_registry_client
from src.config import load_env_config


def promote_model(
    env_name: str,
    model_name: str,
    workspace_model_version: str,
    registry_model_version: str | None = None,
) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)
    registry_client = get_registry_client(config)

    source_model = ml_client.models.get(name=model_name, version=workspace_model_version)
    registry_path = f"azureml:{model_name}:{workspace_model_version}"

    promoted = registry_client.models.create_or_update(
        Model(
            name=model_name,
            version=registry_model_version or str(workspace_model_version),
            path=registry_path,
            type=AssetTypes.CUSTOM_MODEL,
            description=source_model.description,
            tags={
                **(source_model.tags or {}),
                "workspace_model_version": str(workspace_model_version),
                "source_workspace": config["workspace_name"],
                "promoted_from_env": env_name,
            },
        )
    )
    print(
        f"Promoted workspace model {model_name}:{workspace_model_version} "
        f"to registry version {promoted.version}"
    )
    # Azure DevOps output variable for downstream deploy stages.
    print(f"##vso[task.setvariable variable=REGISTRY_MODEL_VERSION;isOutput=true]{promoted.version}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--workspace-model-version", required=True)
    parser.add_argument("--registry-model-version")
    args = parser.parse_args()
    promote_model(
        env_name=args.env,
        model_name=args.model_name,
        workspace_model_version=args.workspace_model_version,
        registry_model_version=args.registry_model_version,
    )


if __name__ == "__main__":
    main()
