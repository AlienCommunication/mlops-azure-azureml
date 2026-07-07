# Used Car System Operating Policy

This document turns the architecture into an explicit operating policy for the used car price prediction system.

## Production Prediction Path

1. A caller sends car attributes to the Azure ML online endpoint.
2. The deployed scoring container runs `src/score.py`.
3. The model returns a predicted resale price.
4. The request payload, prediction, and metadata should be captured with a unique `record_id`.
5. When the actual sale price becomes available later, it should be stored against the same `record_id`.

## Data to Capture in Production

For each inference record, capture:

- `record_id`
- `event_timestamp`
- all model input features
- `predicted_price`
- eventual `actual_price`

The example schema is in [production-schema.json](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/monitoring/production-schema.json).

## What To Monitor

### 1. Service Health

- p95 latency
- error rate
- endpoint availability

### 2. Data Quality

Watch for:

- missing values in required fields
- out-of-bounds numerical values
- unseen categorical values

Required columns:

- `brand`
- `year`
- `mileage`
- `engine_size`
- `fuel_type`
- `transmission`
- `owner_count`
- `service_history_score`
- `accident_count`

### 3. Data Drift

Most important features to monitor:

- `mileage`
- `year`
- `engine_size`
- `fuel_type`
- `brand`
- `service_history_score`
- `accident_count`

Interpretation:

- rising drift means incoming inventory differs from the data the model learned on
- drift alone does not prove accuracy degradation

### 4. Prediction Drift

Monitor the distribution of predicted prices.

Interpretation:

- a shift in prediction distribution may indicate market change, inventory mix change, or upstream data quality problems

### 5. Performance Drift

When labels arrive later, compute:

- rolling RMSE
- rolling MAE

This is the practical signal for concept drift in this use case.

## Thresholds

### Prod defaults

- p95 latency: `400 ms`
- error rate: `2%`
- RMSE threshold: `4500`
- MAE threshold: `3500`
- data drift numerical threshold: `0.08`
- data drift categorical threshold: `0.03`
- prediction drift threshold: `0.08`

## Responsible AI

Run Responsible AI analysis on:

- `brand`
- `fuel_type`
- `year`
- `transmission`

Recommended analyses:

- error analysis by cohort
- feature importance
- counterfactual analysis

Questions to answer:

- Are some brands systematically underpriced or overpriced?
- Are older vehicles producing much larger errors?
- Are manual vs automatic cars handled differently?
- Which features dominate predictions?

## Action Policy

### If data quality fails

- alert platform + ML ops teams
- inspect source-system changes
- do not auto-promote new models
- retrain only if the issue reflects a durable schema or business change

### If data drift rises

- alert ML ops team
- compare drift window with production performance
- if drift is sustained across repeated windows, trigger a retraining candidate pipeline

### If prediction drift rises

- inspect whether inventory mix changed
- check whether drift aligns with business seasonality
- if sustained and paired with worse performance, retrain candidate model

### If performance degrades

- treat as strongest signal
- trigger retraining candidate pipeline
- compare candidate against current prod baseline
- deploy only if candidate passes test and approval gates

## Automation Policy

Recommended automation behavior:

1. Monitoring runs daily.
2. Threshold breach creates alert.
3. Event Grid or orchestrator triggers retraining candidate job for sustained issues.
4. Candidate model is evaluated against production baseline.
5. Candidate deploys automatically to `test`.
6. Smoke tests run automatically.
7. `prod` deployment stays approval-gated.
