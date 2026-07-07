from __future__ import annotations

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential


def get_ml_client(config: dict) -> MLClient:
    credential = DefaultAzureCredential()
    return MLClient(
        credential=credential,
        subscription_id=config["subscription_id"],
        resource_group_name=config["resource_group"],
        workspace_name=config["workspace_name"],
    )


def get_registry_client(config: dict) -> MLClient:
    credential = DefaultAzureCredential()
    return MLClient(
        credential=credential,
        registry_name=config["registry_name"],
    )
