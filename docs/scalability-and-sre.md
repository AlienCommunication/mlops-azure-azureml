# Scalability And SRE Guidance

This project should scale in both training and serving dimensions.

## Training Scalability

Use Azure ML compute clusters with autoscaling:

- smaller CPU cluster for dev
- larger CPU/GPU cluster for prod retraining
- scale down to zero when idle where acceptable

## Serving Scalability

For managed online endpoints:

- start with multiple instances in prod
- tune request timeout
- tune max concurrent requests
- use blue/green deployments for safe rollout

If deeper serving control is required, use Kubernetes online endpoints or a platform-owned serving layer.

## Operational Guardrails

Define:

- latency SLO
- error rate SLO
- recovery / rollback playbook
- canary or staged traffic shifting policy

## Recommended Capacity Pattern

### Dev

- small compute
- low-cost endpoint sizing

### Test

- production-like endpoint behavior
- lower traffic volume

### Prod

- multiple endpoint instances
- autoscaling or higher baseline capacity
- monitoring-driven tuning

## Failure Handling

When prod regression is detected:

1. stop traffic increase
2. shift traffic back to previous deployment
3. preserve failed deployment for investigation
4. review drift, data quality, and runtime logs
