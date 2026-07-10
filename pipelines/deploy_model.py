from __future__ import annotations

import argparse
from pathlib import Path

from azure.ai.ml import command, load_environment
from azure.ai.ml.entities import CodeConfiguration, ManagedOnlineDeployment, ManagedOnlineEndpoint

from src.azure_auth import get_ml_client, get_registry_client
from src.config import load_env_config


def ensure_environment(ml_client):
    # The serving environment must exist in the *target* workspace; it is not
    # inherited from dev, so create/update it here before deploying. Return
    # the created asset so the deployment can pin its exact version —
    # "@latest" label resolution 404s on freshly created environments.
    # Serving uses its own environment (with azureml-inference-server-http),
    # separate from the training environment.
    env_path = Path(__file__).resolve().parent / "environment" / "serve-env.yaml"
    created = ml_client.environments.create_or_update(load_environment(source=env_path))
    print(f"Serving environment ready: {created.name}:{created.version}")
    return created


def ensure_environment_image(ml_client, serving_env, compute_name: str) -> None:
    """Build the serving image via a no-op job before deploying.

    Managed online deployments abort after ~20 minutes waiting for an image
    build, and with a private ACR the build runs as a cluster job whose node
    allocation alone can exceed that. A job build is patient and observable,
    and the resulting image is cached in ACR, so the deployment then starts
    with the image already available.
    """
    attempts = 2
    for attempt in range(1, attempts + 1):
        job = command(
            command="echo serving image ready",
            environment=f"azureml:{serving_env.name}:{serving_env.version}",
            compute=compute_name,
            display_name=f"warm-serving-image-{serving_env.name}-{serving_env.version}",
            experiment_name="serving-image-warmup",
        )
        created = ml_client.jobs.create_or_update(job)
        print(f"Serving image warm-up job (attempt {attempt}/{attempts}): {created.name}")
        try:
            ml_client.jobs.stream(created.name)
        except Exception as exc:
            # Image builds on compute occasionally die with a silent
            # infrastructure timeout; one retry usually succeeds.
            if attempt < attempts:
                print(f"Warm-up attempt {attempt} failed ({exc.__class__.__name__}); retrying once.")
                continue
            raise
        final = ml_client.jobs.get(created.name)
        if final.status == "Completed":
            print("Serving image available in registry cache.")
            return
        if attempt < attempts:
            print(f"Warm-up attempt {attempt} ended in status {final.status}; retrying once.")
            continue
        raise RuntimeError(f"Serving image warm-up job ended in status {final.status}")


def deploy(env_name: str, model_name: str, model_version: str, source: str) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)
    registry_client = get_registry_client(config) if source == "registry" else None
    serving_env = ensure_environment(ml_client)
    ensure_environment_image(ml_client, serving_env, config["compute"]["cpu_cluster"])

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
        # Private posture: scoring is reachable only through the workspace
        # private endpoint, not the public internet.
        public_network_access=config["deployment"].get("public_network_access", "disabled"),
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
        # Required with private ACR/storage: the deployment pulls its image
        # and model over managed private endpoints instead of the internet.
        egress_public_network_access=config["deployment"].get("egress_public_network_access", "disabled"),
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
