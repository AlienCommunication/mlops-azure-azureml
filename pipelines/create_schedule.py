from __future__ import annotations

import argparse
from datetime import datetime, timezone

from azure.ai.ml import Input
from azure.ai.ml.entities import CronTrigger, JobSchedule

from pipelines.training_pipeline import used_car_training_pipeline
from src.azure_auth import get_ml_client
from src.config import load_env_config


def create_schedule(
    env_name: str,
    data_path: str,
    cron_expression: str,
    n_estimators: int,
    max_depth: int,
    min_samples_split: int,
    rmse_threshold: float,
    r2_threshold: float,
) -> None:
    config = load_env_config(env_name)
    ml_client = get_ml_client(config)

    pipeline_job = used_car_training_pipeline(
        train_data=Input(type="uri_file", path=data_path),
        n_estimators=n_estimators,
        max_depth=max_depth,
        min_samples_split=min_samples_split,
        rmse_threshold=rmse_threshold,
        r2_threshold=r2_threshold,
    )
    pipeline_job.settings.default_compute = config["compute"]["cpu_cluster"]
    pipeline_job.experiment_name = "used-car-price-retraining"

    trigger = CronTrigger(
        expression=cron_expression,
        start_time=datetime.now(timezone.utc),
        time_zone="UTC",
    )
    schedule = JobSchedule(
        name=f"used-car-retrain-{env_name}",
        trigger=trigger,
        create_job=pipeline_job,
    )

    ml_client.schedules.begin_create_or_update(schedule).result()
    print(f"Created schedule used-car-retrain-{env_name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--data", required=True)
    parser.add_argument("--cron", default="0 2 * * 1")
    parser.add_argument("--n-estimators", type=int, default=250)
    parser.add_argument("--max-depth", type=int, default=16)
    parser.add_argument("--min-samples-split", type=int, default=2)
    parser.add_argument("--rmse-threshold", type=float, default=5000.0)
    parser.add_argument("--r2-threshold", type=float, default=0.8)
    args = parser.parse_args()
    create_schedule(
        args.env,
        args.data,
        args.cron,
        args.n_estimators,
        args.max_depth,
        args.min_samples_split,
        args.rmse_threshold,
        args.r2_threshold,
    )


if __name__ == "__main__":
    main()
