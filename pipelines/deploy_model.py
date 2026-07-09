from __future__ import annotations

import argparse
from pathlib import Path

from azure.ai.ml import load_environment
from azure.ai.ml.entities import CodeConfiguration, ManagedOnlineDeployment, ManagedOnlineEndpoint

from src.azure_auth import get_ml_client, get_registry_client
from src.config import load_env_config


def ensure_environment(ml_client):
    # The serving environment must exist in the *target* workspace; it is not
    # inherited from dev, so create/update it here before deploying. Return
    # the created asset so the deployment can pin its exact version —
    # "@latest" label resolution 404s on freshly created environments.
    env_path = Path(__file__).resolve().parent / "environment" / "train-env.yaml"
    created = ml_client.environments.create_or_update(load_environment(source=env_path))
    print(f"Serving environment ready: {created.name}:{created.version}")
    return created


def deploy(env_name: str, model_name: str, model_version: str, source: str) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)
    registry_client = get_registry_client(config) if source == "registry" else None
    serving_env = ensure_environment(ml_client)

    endpoint_name = config["deployment"]["endpoint_name"]
    deployment_name = config["deployment"]["deployment_name"]
    model_ref = f"azureml:{model_name}:{model_version}"

    if source == "registry":
        registry_client.models.get(name=model_name, version=model_version)
        model_ref = f"azureml://registries/{config['registry_name']}/models/{model_name}/versions/{model_version}"
    else:
        ml_client.models.get(name=model_name, version=model_version)

    endpoint = ManagedOnlineEndpoint(
        name=endpoint_name,
        description=f"Used car price endpoint for {env_name}",
        auth_mode="key",
        tags=config["tags"],
    )
    ml_client.online_endpoints.begin_create_or_update(endpoint).result()

    deployment = ManagedOnlineDeployment(
        name=deployment_name,
        endpoint_name=endpoint_name,
        model=model_ref,
        code_configuration=CodeConfiguration(code=".", scoring_script="src/score.py"),
        environment=f"azureml:{serving_env.name}:{serving_env.version}",
        instance_type=config["deployment"]["instance_type"],
        instance_count=config["deployment"]["instance_count"],
    )

    ml_client.online_deployments.begin_create_or_update(deployment).result()
    live_endpoint = ml_client.online_endpoints.get(endpoint_name)
    live_endpoint.traffic = {deployment_name: 100}
    ml_client.online_endpoints.begin_create_or_update(live_endpoint).result()
    print(f"Deployed {model_name}:{model_version} to {endpoint_name}/{deployment_name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--model-version", required=True)
    parser.add_argument("--source", choices=["workspace", "registry"], default="registry")
    args = parser.parse_args()
    deploy(args.env, args.model_name, args.model_version, args.source)


if __name__ == "__main__":
    main()
