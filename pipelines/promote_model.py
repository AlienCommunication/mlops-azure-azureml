from __future__ import annotations

import argparse

from azure.core.exceptions import ResourceNotFoundError

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

    target_version = str(registry_model_version or workspace_model_version)

    try:
        existing = registry_client.models.get(name=model_name, version=target_version)
        print(f"Model already in registry: {model_name}:{existing.version}; skipping promotion.")
    except ResourceNotFoundError:
        ml_client.models.share(
            name=model_name,
            version=str(workspace_model_version),
            share_with_name=model_name,
            share_with_version=target_version,
            registry_name=config["registry_name"],
        )
        print(
            f"Promoted workspace model {model_name}:{workspace_model_version} "
            f"to registry {config['registry_name']} as version {target_version}"
        )

    # Azure DevOps output variable for downstream deploy stages.
    print(f"##vso[task.setvariable variable=REGISTRY_MODEL_VERSION;isOutput=true]{target_version}")


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
