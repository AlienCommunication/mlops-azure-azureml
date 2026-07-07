from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


BRANDS = ["Toyota", "Honda", "Ford", "Hyundai", "BMW", "Mercedes", "Audi", "Kia"]
FUEL_TYPES = ["Petrol", "Diesel", "Hybrid", "Electric"]
TRANSMISSIONS = ["Manual", "Automatic"]


def build_dataset(rows: int, seed: int) -> pd.DataFrame:
    rng = np.random.default_rng(seed)

    brand = rng.choice(BRANDS, size=rows, p=[0.18, 0.16, 0.15, 0.15, 0.1, 0.08, 0.08, 0.1])
    year = rng.integers(2008, 2025, size=rows)
    mileage = rng.integers(5_000, 220_000, size=rows)
    engine_size = np.round(rng.uniform(1.0, 4.0, size=rows), 1)
    fuel_type = rng.choice(FUEL_TYPES, size=rows, p=[0.45, 0.28, 0.18, 0.09])
    transmission = rng.choice(TRANSMISSIONS, size=rows, p=[0.58, 0.42])
    owner_count = rng.integers(1, 5, size=rows)
    service_history_score = rng.integers(40, 100, size=rows)
    accident_count = rng.integers(0, 3, size=rows)

    brand_multiplier = {
        "Toyota": 1.0,
        "Honda": 1.02,
        "Ford": 0.95,
        "Hyundai": 0.93,
        "BMW": 1.35,
        "Mercedes": 1.45,
        "Audi": 1.32,
        "Kia": 0.92,
    }
    fuel_bonus = {"Petrol": 0, "Diesel": 1200, "Hybrid": 2800, "Electric": 5000}
    transmission_bonus = {"Manual": 0, "Automatic": 1800}

    base_price = 25000 + (year - 2008) * 1200
    price = (
        base_price
        - mileage * 0.06
        + engine_size * 1800
        + np.vectorize(fuel_bonus.get)(fuel_type)
        + np.vectorize(transmission_bonus.get)(transmission)
        - owner_count * 700
        + service_history_score * 55
        - accident_count * 1500
    )
    price = price * np.vectorize(brand_multiplier.get)(brand)
    price = price + rng.normal(0, 2500, size=rows)
    price = np.clip(price, 3000, None).round(2)

    return pd.DataFrame(
        {
            "brand": brand,
            "year": year,
            "mileage": mileage,
            "engine_size": engine_size,
            "fuel_type": fuel_type,
            "transmission": transmission,
            "owner_count": owner_count,
            "service_history_score": service_history_score,
            "accident_count": accident_count,
            "price": price,
        }
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", type=Path, default=Path("data/used_cars.csv"))
    args = parser.parse_args()

    df = build_dataset(args.rows, args.seed)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    print(f"Wrote {len(df)} rows to {args.output}")


if __name__ == "__main__":
    main()
