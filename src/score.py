from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import joblib
import pandas as pd

# The inference server puts the entry script's directory (src/) on sys.path,
# not the code root, so make `src.features` importable explicitly.
_CODE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _CODE_ROOT not in sys.path:
    sys.path.insert(0, _CODE_ROOT)

from src.features import FEATURE_COLUMNS, encode_dataframe  # noqa: E402

model = None


def _find_model_file() -> Path:
    # Models registered from job output folders mount with their folder
    # structure preserved, so search instead of assuming a flat layout.
    root = Path(os.getenv("AZUREML_MODEL_DIR", "."))
    matches = sorted(root.rglob("model.joblib")) or sorted(root.rglob("*.joblib"))
    if not matches:
        contents = [str(p.relative_to(root)) for p in root.rglob("*")][:50]
        raise FileNotFoundError(f"No .joblib model found under {root}; contents: {contents}")
    return matches[0]


def init() -> None:
    global model
    model_file = _find_model_file()
    print(f"Loading model from {model_file}", flush=True)
    model = joblib.load(model_file)
    print("Model loaded.", flush=True)


def run(raw_data: str) -> str:
    if model is None:
        raise RuntimeError("Model is not initialized. Call init() before run().")
    data = pd.DataFrame(json.loads(raw_data))
    encoded = encode_dataframe(data)
    preds = model.predict(encoded[FEATURE_COLUMNS]).tolist()
    return json.dumps({"predictions": preds})
