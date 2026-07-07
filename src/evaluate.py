from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--metrics_input", type=Path, required=True)
    parser.add_argument("--evaluation_output", type=Path, required=True)
    parser.add_argument("--rmse_threshold", type=float, default=5000.0)
    parser.add_argument("--r2_threshold", type=float, default=0.8)
    args = parser.parse_args()

    metrics = json.loads(args.metrics_input.read_text())
    approved = metrics["rmse"] <= args.rmse_threshold and metrics["r2"] >= args.r2_threshold

    result = {
        "approved": approved,
        "rmse_threshold": args.rmse_threshold,
        "r2_threshold": args.r2_threshold,
        "metrics": metrics,
    }

    args.evaluation_output.parent.mkdir(parents=True, exist_ok=True)
    args.evaluation_output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
