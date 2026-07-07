# Monitoring and Retraining

The used-car-specific operating policy is documented in [used-car-operating-policy.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/used-car-operating-policy.md). The production monitor template is in [used-car-monitoring.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/monitoring/used-car-monitoring.yaml).

## Monitoring Design

For a production endpoint, monitor four categories:

1. Service health
- request count
- latency percentiles
- 4xx and 5xx rates
- container restarts

2. Data quality
- null spikes
- schema drift
- range violations
- categorical novelty

3. Data and prediction drift
- drift from baseline training data
- distribution shift in predicted prices
- alert threshold breaches

4. Business outcome quality
- compare predictions with actual sold prices when labels arrive later
- compute MAE/RMSE over rolling windows

## Alerting

Typical alerts:

- p95 latency above threshold
- endpoint error rate above threshold
- drift score above threshold
- rolling RMSE above policy threshold

## Retraining Patterns

### Scheduled Retraining

- weekly or monthly AML schedule
- suitable when labels arrive on a predictable cadence

### Event-Driven Retraining

- external orchestrator detects new parquet/csv partitions
- triggers AML pipeline through SDK, CLI, or batch endpoint

### Drift-Triggered Retraining

- monitoring system sends event
- automation workflow creates retraining run

## Safe Promotion Policy

Promote only if:

- candidate RMSE is lower than production baseline by a defined margin, or
- candidate is statistically no worse and passes stability and drift checks

## Human-in-the-Loop

For regulated enterprise settings:

- require approval before prod deploy
- capture approver identity
- retain model card / metrics / evaluation report
