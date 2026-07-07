from __future__ import annotations

import argparse
import json

from src.azure_auth import get_ml_client
from src.config import load_env_config


SAMPLE_PAYLOAD = [
    {
        "brand": "Toyota",
        "year": 2020,
        "mileage": 35000,
        "engine_size": 1.8,
        "fuel_type": "Hybrid",
        "transmission": "Automatic",
        "owner_count": 1,
        "service_history_score": 92,
        "accident_count": 0,
    }
]


def smoke_test(env_name: str, endpoint_name: str | None = None, deployment_name: str | None = None) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)

    endpoint = endpoint_name or config["deployment"]["endpoint_name"]
    deployment = deployment_name or config["deployment"]["deployment_name"]

    response = ml_client.online_endpoints.invoke(
        endpoint_name=endpoint,
        deployment_name=deployment,
        request_file=None,
        input_data=json.dumps(SAMPLE_PAYLOAD),
    )
    print(response)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--endpoint-name")
    parser.add_argument("--deployment-name")
    args = parser.parse_args()
    smoke_test(args.env, args.endpoint_name, args.deployment_name)


if __name__ == "__main__":
    main()
