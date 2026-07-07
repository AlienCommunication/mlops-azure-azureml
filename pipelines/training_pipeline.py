from __future__ import annotations

from pathlib import Path

from azure.ai.ml import Input, dsl, load_component


ROOT = Path(__file__).resolve().parent

train_component = load_component(source=ROOT / "components" / "train_component.yaml")
evaluate_component = load_component(source=ROOT / "components" / "evaluate_component.yaml")


@dsl.pipeline(
    description="Train and evaluate used car price model",
)
def used_car_training_pipeline(
    train_data: str,
    n_estimators: int = 250,
    max_depth: int = 16,
    min_samples_split: int = 2,
    rmse_threshold: float = 5000.0,
    r2_threshold: float = 0.8,
):
    train_step = train_component(
        train_data=Input(type="uri_file", path=train_data),
        n_estimators=n_estimators,
        max_depth=max_depth,
        min_samples_split=min_samples_split,
    )

    evaluate_step = evaluate_component(
        metrics_input=train_step.outputs.metrics_output,
        rmse_threshold=rmse_threshold,
        r2_threshold=r2_threshold,
    )

    return {
        "model_output": train_step.outputs.model_output,
        "metrics_output": train_step.outputs.metrics_output,
        "evaluation_output": evaluate_step.outputs.evaluation_output,
    }
