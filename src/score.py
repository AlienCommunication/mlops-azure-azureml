from __future__ import annotations

import json
import os

import joblib
import pandas as pd

from src.features import FEATURE_COLUMNS, encode_dataframe

model = None


def init() -> None:
    global model
    model_path = os.path.join(os.getenv("AZUREML_MODEL_DIR", "."), "model.joblib")
    model = joblib.load(model_path)


def run(raw_data: str) -> str:
    if model is None:
        raise RuntimeError("Model is not initialized. Call init() before run().")
    data = pd.DataFrame(json.loads(raw_data))
    encoded = encode_dataframe(data)
    preds = model.predict(encoded[FEATURE_COLUMNS]).tolist()
    return json.dumps({"predictions": preds})
