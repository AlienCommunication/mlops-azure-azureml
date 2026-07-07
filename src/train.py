from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

from src.features import FEATURE_COLUMNS, TARGET_COLUMN, encode_dataframe

try:
    import mlflow
except ImportError:  # pragma: no cover - exercised only in minimal local setups
    mlflow = None


def train_model(
    train_path: Path,
    model_dir: Path,
    metrics_path: Path,
    n_estimators: int,
    max_depth: int | None,
    min_samples_split: int,
    random_state: int,
) -> dict[str, Any]:
    df = pd.read_csv(train_path)
    df = encode_dataframe(df)

    X = df[FEATURE_COLUMNS]
    y = df[TARGET_COLUMN]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=random_state
    )

    model = RandomForestRegressor(
        n_estimators=n_estimators,
        max_depth=max_depth,
        min_samples_split=min_samples_split,
        random_state=random_state,
        n_jobs=-1,
    )
    model.fit(X_train, y_train)
    preds = model.predict(X_test)

    rmse = float(np.sqrt(mean_squared_error(y_test, preds)))
    mae = float(mean_absolute_error(y_test, preds))
    r2 = float(r2_score(y_test, preds))

    model_dir.mkdir(parents=True, exist_ok=True)
    metrics_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, model_dir / "model.joblib")

    metrics = {"rmse": rmse, "mae": mae, "r2": r2}
    metrics_path.write_text(json.dumps(metrics, indent=2))

    if mlflow is not None:
        mlflow.log_params(
            {
                "n_estimators": n_estimators,
                "max_depth": max_depth if max_depth is not None else -1,
                "min_samples_split": min_samples_split,
            }
        )
        mlflow.log_metrics(metrics)
        mlflow.log_artifact(str(metrics_path))
        mlflow.log_artifacts(str(model_dir), artifact_path="model")

    return metrics


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train_data", type=Path, required=True)
    parser.add_argument("--model_output", type=Path, required=True)
    parser.add_argument("--metrics_output", type=Path, required=True)
    parser.add_argument("--n_estimators", type=int, default=250)
    parser.add_argument("--max_depth", type=int, default=16)
    parser.add_argument("--min_samples_split", type=int, default=2)
    parser.add_argument("--random_state", type=int, default=42)
    args = parser.parse_args()

    if mlflow is not None:
        with mlflow.start_run():
            metrics = train_model(
                train_path=args.train_data,
                model_dir=args.model_output,
                metrics_path=args.metrics_output,
                n_estimators=args.n_estimators,
                max_depth=args.max_depth,
                min_samples_split=args.min_samples_split,
                random_state=args.random_state,
            )
    else:
        metrics = train_model(
            train_path=args.train_data,
            model_dir=args.model_output,
            metrics_path=args.metrics_output,
            n_estimators=args.n_estimators,
            max_depth=args.max_depth,
            min_samples_split=args.min_samples_split,
            random_state=args.random_state,
        )
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
