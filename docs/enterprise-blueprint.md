# Enterprise Blueprint

## Environments

### Dev

- workspace for experimentation and fast iteration
- component registration and validation
- candidate model training

### Test

- integration validation
- endpoint smoke tests
- pre-production approval gate

### Prod

- production deployment
- monitoring, drift detection, and controlled rollout

## Central Registry

Use a dedicated Azure ML registry to store:

- approved models
- reusable components
- curated environments

This lets teams promote artifacts across workspaces cleanly instead of copying local artifacts between subscriptions or workspaces.

## CI/CD Lanes

### CI Lane

Triggers:

- pull request
- push to feature branches

Responsibilities:

- lint and unit test training code
- validate YAML and pipeline construction
- optionally run a local smoke training job on a sample dataset

Recommended engine:

- Azure DevOps pipeline connected to GitHub repo

### Platform Lane

Triggers:

- infrastructure change
- controlled manual release

Responsibilities:

- deploy or update resource groups
- deploy or update AML workspaces
- deploy shared registry and supporting resources
- configure identities, Key Vault, and monitoring foundations

### CD Lane: Dev

Triggers:

- merge to `main`

Responsibilities:

- register environment and components
- submit training pipeline to `dev`
- evaluate candidate model
- register approved model in workspace

### CD Lane: Test

Triggers:

- manual approval after dev success

Responsibilities:

- promote model to registry
- deploy to `test`
- run smoke inference tests

### CD Lane: Prod

Triggers:

- manual approval after test validation

Responsibilities:

- deploy approved registry model to `prod`
- shift endpoint traffic to new deployment
- leave previous deployment available for rollback

## Infrastructure Layer

This blueprint now includes starter Bicep templates for:

- resource group per environment
- Azure ML workspace per environment
- storage, Key Vault, ACR, Application Insights, and Log Analytics
- optional shared Azure ML registry

Recommended enterprise pattern:

1. deploy shared registry once
2. deploy `dev`, `test`, and `prod` workspaces separately
3. attach private networking and policy controls in your platform layer

## Monitoring Lane

Production monitoring should include:

- request latency and failure rate
- data drift against baseline training distribution
- prediction drift
- optional accuracy monitoring when ground truth becomes available
- endpoint container logs and app insights traces

## Retraining Lane

Retraining can be triggered by:

- time schedule
- monitoring alert
- data refresh event from Fabric or Data Factory
- business-driven refresh window

Recommended pattern:

1. trigger retraining in `dev` or dedicated training workspace
2. evaluate against production baseline
3. promote only if candidate exceeds policy thresholds
4. deploy via test -> prod promotion

## Promotion Flow

Separate these concerns explicitly:

1. `register_model.py`
   Creates a workspace model after evaluation success.
2. `promote_model.py`
   Promotes an approved workspace model version into the shared registry.
3. `deploy_model.py`
   Deploys from either workspace or registry, with `registry` as the default production path.

## Security Controls

- managed identities for compute and deployment
- Key Vault backed secrets
- Azure DevOps service connections or workload identity federation for CI/CD
- RBAC per workspace and registry
- private endpoints for workspace dependencies
- separate resource groups for dev/test/prod

## Rollback

Managed online endpoints support safe rollout by keeping a stable deployment beside a candidate deployment.

Recommended strategy:

- deploy `green` beside `blue`
- smoke test candidate
- shift 10% traffic, then 100%
- revert traffic on regression
