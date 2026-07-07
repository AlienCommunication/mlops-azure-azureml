from __future__ import annotations

import argparse
import json
from pathlib import Path

from src.config import load_env_config


def generate(env_name: str, output_path: Path) -> None:
    config = load_env_config(env_name)
    payload = {
        "environment": env_name,
        "endpoint_name": config["deployment"]["endpoint_name"],
        "latency_threshold_ms": config["monitoring"]["latency_threshold_ms"],
        "error_rate_threshold": config["monitoring"]["error_rate_threshold"],
        "data_drift_baseline_days": config["monitoring"]["data_drift_baseline_days"],
        "application_insights_enabled": config["monitoring"]["application_insights_enabled"],
        "performance": config["monitoring"]["performance"],
        "input_data_quality": config["monitoring"]["input_data_quality"],
        "drift": config["monitoring"]["drift"],
        "actions": config["monitoring"]["actions"],
        "responsible_ai": config["monitoring"]["responsible_ai"],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2))
    print(output_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    generate(args.env, args.output)


if __name__ == "__main__":
    main()
