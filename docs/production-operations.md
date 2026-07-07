# Production Operations

This document defines the intended enterprise operating sequence.

## Primary Path

1. Platform pipeline provisions or updates Azure resources.
2. Data pipeline lands production-approved training data into storage.
3. Azure ML training pipeline consumes registered data assets.
4. Evaluation gate decides whether workspace model is eligible.
5. Promotion pipeline moves approved model to the registry.
6. Deployment pipeline pushes registry model to test.
7. Smoke tests run.
8. Approval gate controls prod rollout.
9. Monitoring and retraining automation run continuously after deployment.

## Developer Path

Local scripts remain available only for:

- onboarding
- smoke testing
- isolated debugging

They are not the intended enterprise operating path.
