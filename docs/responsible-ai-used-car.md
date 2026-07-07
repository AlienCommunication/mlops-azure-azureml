# Responsible AI for Used Car Price Prediction

## Purpose

Responsible AI for this use case is not just a governance checkbox. It helps answer whether the model behaves unevenly across vehicle cohorts and whether prediction logic is understandable.

## Recommended Dashboard Components

- data exploration
- model interpretability
- error analysis
- counterfactual analysis

## Cohorts To Review

- `brand`
- `fuel_type`
- `transmission`
- `year` bands
- `mileage` bands

## What To Look For

### Error Analysis

Check whether model errors cluster around:

- luxury brands
- older high-mileage cars
- hybrid/electric vehicles
- rare inventory segments

### Interpretability

Expected high-importance features in this domain:

- mileage
- year
- engine size
- accident count
- service history score

If feature importance behaves strangely, inspect data leakage or feature quality.

### Counterfactuals

Useful business questions:

- What minimal changes would move a predicted price from `7L` to `8L`?
- How much does accident history change a prediction?
- How much does a better service history improve price?

## When To Run Responsible AI

- before first prod deployment
- after major retraining cycles
- when performance degradation is reported
- when business stakeholders suspect bias or unexplained pricing behavior
