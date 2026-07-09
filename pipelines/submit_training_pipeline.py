from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path

from azure.ai.ml import load_environment
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Model

from pipelines.training_pipeline import used_car_training_pipeline
from src.azure_auth import get_ml_client
from src.config import load_env_config


def ensure_environment(ml_client) -> None:
    env_path = Path(__file__).resolve().parent / "environment" / "train-env.yaml"
    environment = load_environment(source=env_path)
    ml_client.environments.create_or_update(environment)


def load_evaluation(ml_client, job_name: str) -> dict:
    with tempfile.TemporaryDirectory() as tmp_dir:
        ml_client.jobs.download(
            name=job_name,
            output_name="evaluation_output",
            download_path=tmp_dir,
        )
        eval_files = sorted(Path(tmp_dir).rglob("*.json"))
        if not eval_files:
            raise FileNotFoundError(
                f"No evaluation JSON found in downloaded output for job {job_name}"
            )
        return json.loads(eval_files[0].read_text())


def register_model_from_job(ml_client, config: dict, job_name: str, evaluation: dict) -> str:
    model = Model(
        name=config["model_name"],
        path=f"azureml://jobs/{job_name}/outputs/model_output",
        type=AssetTypes.CUSTOM_MODEL,
        description="Used car price model registered from approved training job.",
        tags={
            **config["tags"],
            "training_job": job_name,
            "rmse": str(evaluation["metrics"]["rmse"]),
            "r2": str(evaluation["metrics"]["r2"]),
        },
    )
    created = ml_client.models.create_or_update(model)
    print(f"Registered workspace model {created.name}:{created.version}")
    return str(created.version)


def submit(
    env_name: str,
    data_path: str,
    n_estimators: int,
    max_depth: int,
    min_samples_split: int,
    rmse_threshold: float,
    r2_threshold: float,
    wait: bool,
    register_model: bool,
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

    if not wait:
        return

    # Stream logs until the job reaches a terminal state; raises on failure.
    ml_client.jobs.stream(created.name)

    final_job = ml_client.jobs.get(created.name)
    if final_job.status != "Completed":
        raise RuntimeError(f"Training job {created.name} ended in status {final_job.status}")

    evaluation = load_evaluation(ml_client, created.name)
    print(json.dumps(evaluation, indent=2))
    if not evaluation.get("approved", False):
        raise RuntimeError(
            "Model rejected by evaluation gate; not registering. "
            f"Metrics: {evaluation.get('metrics')}"
        )

    if register_model:
        version = register_model_from_job(ml_client, config, created.name, evaluation)
        # Azure DevOps output variable for downstream stages.
        print(f"##vso[task.setvariable variable=WORKSPACE_MODEL_VERSION;isOutput=true]{version}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--data", required=True)
    parser.add_argument("--n-estimators", type=int, default=250)
    parser.add_argument("--max-depth", type=int, default=16)
    parser.add_argument("--min-samples-split", type=int, default=2)
    parser.add_argument("--rmse-threshold", type=float, default=5000.0)
    parser.add_argument("--r2-threshold", type=float, default=0.8)
    parser.add_argument("--wait", action="store_true", help="Stream the job and fail on non-completion.")
    parser.add_argument(
        "--register-model",
        action="store_true",
        help="After a successful, approved run, register the model and emit WORKSPACE_MODEL_VERSION.",
    )
    args = parser.parse_args()
    submit(
        args.env,
        args.data,
        args.n_estimators,
        args.max_depth,
        args.min_samples_split,
        args.rmse_threshold,
        args.r2_threshold,
        wait=args.wait,
        register_model=args.register_model,
    )


if __name__ == "__main__":
    main()
