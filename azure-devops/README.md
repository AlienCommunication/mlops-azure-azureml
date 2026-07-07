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
- Azure Key Vault for secret storage
- Azure DevOps variable groups for non-secret Terraform inputs
- Azure DevOps secret variable or Key Vault-backed variable for `AZURE_DEVOPS_PAT` during Terraform bootstrap to the Azure DevOps provider
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

- `AZURE_DEVOPS_PAT` as a secret variable or Key Vault-backed secret for the Terraform infra pipeline
- non-secret Terraform inputs as pipeline variables or variable-group variables using `TF_VAR_...` names
- `WORKSPACE_MODEL_VERSION`
- `REGISTRY_MODEL_VERSION`
- optional environment-specific overrides

## Terraform Input Pattern

For production CI/CD, do not depend on a developer-local `terraform.tfvars` file.

Recommended pattern:

1. store secrets in Azure Key Vault
2. expose secrets to Azure DevOps through a Key Vault-backed variable group or secret pipeline variables
3. expose non-secret Terraform inputs through Azure DevOps variables or variable groups using `TF_VAR_...` names
4. let the Terraform pipeline consume those environment variables directly

Examples of non-secret Terraform inputs to define in Azure DevOps:

- `TF_VAR_subscription_id`
- `TF_VAR_subscription_name`
- `TF_VAR_tenant_id`
- `TF_VAR_location`
- `TF_VAR_prefix`
- `TF_VAR_registry_name`
- `TF_VAR_azure_devops_org_service_url`
- `TF_VAR_azure_devops_project_name`
- `TF_VAR_service_connection_name`
- `TF_VAR_azure_auth_mode`

Examples of secret Terraform inputs to source from Key Vault:

- `AZURE_DEVOPS_PAT`
- `TF_VAR_service_principal_key` if secret-based auth is still used

## Where To Add Them In Azure DevOps

Use two different Azure DevOps locations:

1. `Pipelines -> Library -> Variable groups`
   Use this for non-secret Terraform inputs such as:
   - `TF_VAR_subscription_id`
   - `TF_VAR_location`
   - `TF_VAR_prefix`
   - `TF_VAR_azure_devops_project_name`

2. `Pipeline -> Edit -> Variables`
   Use this for direct pipeline variables and secrets such as:
   - `AZURE_DEVOPS_PAT`

Important:

- `aml-infra-tfvars` is a Library variable group
- it is not added from the `New variable` popup
- this repo's infrastructure pipeline references it directly in YAML

## Production Notes

- Infra provisioning is intentionally its own stage and should also be runnable independently.
- Prod deployment should remain environment approval-gated.
- Replace placeholder variable names and service connection names with your organization standards.
