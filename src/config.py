from __future__ import annotations

import os
from pathlib import Path
from string import Template
from typing import Any

import yaml


PROJECT_ROOT = Path(__file__).resolve().parent.parent
CONFIGS_DIR = PROJECT_ROOT / "configs"


def _substitute_env(raw_text: str) -> str:
    return Template(raw_text).safe_substitute(os.environ)


def load_env_config(env_name: str) -> dict[str, Any]:
    config_path = CONFIGS_DIR / f"{env_name}.yaml"
    if not config_path.exists():
        raise FileNotFoundError(f"Missing config: {config_path}")
    rendered = _substitute_env(config_path.read_text())
    return yaml.safe_load(rendered)
