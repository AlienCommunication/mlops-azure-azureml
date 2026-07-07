from __future__ import annotations

import argparse
from pathlib import Path

from azure.ai.ml import load_environment

from pipelines.training_pipeline import used_car_training_pipeline
from src.azure_auth import get_ml_client
from src.config import load_env_config


def ensure_environment(ml_client) -> None:
    env_path = Path(__file__).resolve().parent / "environment" / "train-env.yaml"
    environment = load_environment(source=env_path)
    ml_client.environments.create_or_update(environment)


def submit(
    env_name: str,
    data_path: str,
    n_estimators: int,
    max_depth: int,
    min_samples_split: int,
    rmse_threshold: float,
    r2_threshold: float,
) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)
    ensure_environment(ml_client)

    pipeline_job = used_car_training_pipeline(
        train_data=data_path,
        n_estimators=n_estimators,
        max_depth=max_depth,
        min_samples_split=min_samples_split,
        rmse_threshold=rmse_threshold,
        r2_threshold=r2_threshold,
    )
    pipeline_job.settings.default_compute = config["compute"]["cpu_cluster"]
    pipeline_job.display_name = f"used-car-training-{env_name}"
    pipeline_job.experiment_name = "used-car-price-training"
    pipeline_job.tags = config["tags"]

    created = ml_client.jobs.create_or_update(pipeline_job)
    print(f"Submitted job: {created.name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--data", required=True)
    parser.add_argument("--n-estimators", type=int, default=250)
    parser.add_argument("--max-depth", type=int, default=16)
    parser.add_argument("--min-samples-split", type=int, default=2)
    parser.add_argument("--rmse-threshold", type=float, default=5000.0)
    parser.add_argument("--r2-threshold", type=float, default=0.8)
    args = parser.parse_args()
    submit(
        args.env,
        args.data,
        args.n_estimators,
        args.max_depth,
        args.min_samples_split,
        args.rmse_threshold,
        args.r2_threshold,
    )


if __name__ == "__main__":
    main()
