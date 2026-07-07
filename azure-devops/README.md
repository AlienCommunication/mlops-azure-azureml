# Azure DevOps Pipelines

This folder contains the enterprise-first CI/CD entrypoints for the Azure ML platform and model lifecycle.

## Pipeline Split

### `azure-pipelines-infra.yml`

Dedicated Terraform infrastructure pipeline for:

- `terraform fmt -check`
- `terraform init`
- `terraform validate`
- `terraform plan`
- approval-gated `terraform apply`

### `azure-pipelines.yml`

Primary multi-stage pipeline for:

- validation
- AML training submission
- registry promotion
- test deployment
- prod deployment
- monitoring config generation

### `azure-pipelines-monitoring.yml`

Separate scheduled monitoring-oriented pipeline for:

- generating production monitoring policy artifacts
- integrating with a broader monitor/retrain workflow

## Recommended Azure DevOps Setup

Use:

- GitHub as the source repository
- Azure DevOps pipeline YAML from this folder
- Azure DevOps secret variable `AZURE_DEVOPS_PAT` for Terraform bootstrap to the Azure DevOps provider
- Azure Resource Manager service connection for deployment
- Azure DevOps Environments for `aml-test-approval`, `aml-test`, and `aml-prod`
- Azure DevOps Environment `aml-platform-infra` for approval-gated Terraform apply
- Variable groups backed by Azure Key Vault for non-code secrets

## Recommended Execution Order

1. run `azure-pipelines-infra.yml` to provision or update platform resources
2. verify Terraform apply succeeded
3. run `azure-pipelines.yml` for AML training, promotion, deployment, and monitoring

The ML pipeline should not be the first place where platform provisioning is attempted.

## Required Variables

Pipeline variables or variable groups should provide:

- `AZURE_DEVOPS_PAT` as a secret variable for the Terraform infra pipeline
- `WORKSPACE_MODEL_VERSION`
- `REGISTRY_MODEL_VERSION`
- optional environment-specific overrides

## Production Notes

- Infra provisioning is intentionally its own stage and should also be runnable independently.
- Prod deployment should remain environment approval-gated.
- Replace placeholder variable names and service connection names with your organization standards.
