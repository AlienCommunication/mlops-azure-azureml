from __future__ import annotations

import pandas as pd


FEATURE_COLUMNS = [
    "year",
    "mileage",
    "engine_size",
    "brand_encoded",
    "fuel_type_encoded",
    "transmission_encoded",
    "owner_count",
    "service_history_score",
    "accident_count",
]

TARGET_COLUMN = "price"


BRAND_MAP = {
    "Toyota": 0,
    "Honda": 1,
    "Ford": 2,
    "Hyundai": 3,
    "BMW": 4,
    "Mercedes": 5,
    "Audi": 6,
    "Kia": 7,
}

FUEL_MAP = {
    "Petrol": 0,
    "Diesel": 1,
    "Hybrid": 2,
    "Electric": 3,
}

TRANSMISSION_MAP = {
    "Manual": 0,
    "Automatic": 1,
}


def encode_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    data = df.copy()
    required_columns = {
        "brand",
        "year",
        "mileage",
        "engine_size",
        "fuel_type",
        "transmission",
        "owner_count",
        "service_history_score",
        "accident_count",
    }
    missing = sorted(required_columns.difference(data.columns))
    if missing:
        raise ValueError(f"Missing required input columns: {missing}")

    data["brand_encoded"] = data["brand"].map(BRAND_MAP)
    data["fuel_type_encoded"] = data["fuel_type"].map(FUEL_MAP)
    data["transmission_encoded"] = data["transmission"].map(TRANSMISSION_MAP)

    encoded_columns = ["brand_encoded", "fuel_type_encoded", "transmission_encoded"]
    if data[encoded_columns].isnull().any().any():
        raise ValueError(
            "Found unsupported categorical values in brand, fuel_type, or transmission."
        )

    return data
