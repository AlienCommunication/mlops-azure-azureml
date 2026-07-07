# Terraform Provisioning

This folder is the preferred production-grade provisioning path for this repo.

It is designed to manage both:

- Azure resources
- Azure DevOps resources

using one infrastructure-as-code approach.

## What This Terraform Starter Covers

### Azure resources

- resource groups
- shared VNet
- private endpoint subnet
- self-hosted agent subnet
- private DNS zones
- private endpoints for storage, Key Vault, and ACR
- storage accounts
- Key Vault
- ACR
- Log Analytics
- Application Insights
- Azure ML workspaces

### Azure DevOps resources

- Azure Resource Manager service connection starter
- Azure DevOps environments
- Azure DevOps variable groups
- Key Vault-linked variable groups

## Why Terraform Here

Terraform is a better fit than Bicep when you want one tool to orchestrate:

- Azure Resource Manager resources
- Azure DevOps resources

This avoids a split IaC story for the production path.

## Provider Notes

This starter uses:

- `azurerm`
- `azapi`
- `azuredevops`

`azapi` is included because Azure ML resources sometimes move faster than the higher-level provider surface.

## Current Design Choices For This Tenant

The currently documented target choices are:

- region: `eastus`
- naming prefix: `usedcar`
- private networking from day 1: `enabled`
- self-hosted Azure DevOps agents: `enabled`
- private endpoints for:
  - storage
  - Key Vault
  - ACR
- Terraform bootstrap to Azure DevOps: `PAT`
- Azure DevOps pipeline access to Azure: `workload identity federation`

## Recommended Secret Handling For The Azure DevOps PAT

Do not store the Azure DevOps PAT in:

- `terraform.tfvars`
- committed files
- reusable plaintext scripts

Recommended pattern:

1. store the PAT in Azure Key Vault
2. fetch it just before running Terraform
3. export it as `TF_VAR_azure_devops_pat`

Example:

```bash
export TF_VAR_azure_devops_pat="$(az keyvault secret show \
  --vault-name <your-keyvault-name> \
  --name azure-devops-pat \
  --query value -o tsv)"
```

Then run:

```bash
terraform init
terraform validate
terraform plan
```

## CI/CD Variable Strategy

For Azure DevOps pipeline execution, do not assume a checked-in or locally-created `terraform.tfvars` file exists.

Preferred production pattern:

1. store secrets in Azure Key Vault
2. expose those secrets into Azure DevOps through Key Vault-backed variable groups or secret pipeline variables
3. store non-secret Terraform inputs in Azure DevOps variable groups using `TF_VAR_...` names
4. run Terraform without depending on `-var-file=terraform.tfvars`

Examples of non-secret Azure DevOps variables:

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

Examples of secret Azure-hosted inputs:

- `AZURE_DEVOPS_PAT`
- `TF_VAR_service_principal_key` if secret-based ARM connection mode is used

## Terraform Version Requirement

This project requires:

- Terraform `>= 1.6.0`

If `terraform init` fails with an error like:

```text
Unsupported Terraform Core version
```

your local Terraform binary is too old.

## macOS Homebrew Fix For Terraform 1.5.x

If you see behavior like:

- `brew upgrade terraform` says `terraform 1.5.7 already installed`
- `tfenv install ...` fails because `tfenv` is not on your `PATH`
- Homebrew says `Could not symlink bin/terraform`

then the old Homebrew `terraform` binary is still linked at `/opt/homebrew/bin/terraform`.

Use this sequence:

```bash
brew install tfenv
brew unlink terraform
brew link tfenv
tfenv install 1.9.8
tfenv use 1.9.8
terraform version
```

Expected result:

- `terraform version` shows a version `>= 1.6.0`

If `tfenv` is still not found, start a new shell and re-run:

```bash
tfenv --version
terraform version
```

Only continue to `terraform init` after the version check passes.

## Important Limitation Notes

- Azure DevOps and Azure are still different control planes, even when managed by one Terraform workflow.
- Approval checks and some advanced Azure DevOps governance features may still require supplemental configuration depending on provider feature parity.
- If your organization requires workload identity federation for service connections, you may need to adapt the service connection resource shape to your exact provider version and enterprise policy.
- The current Terraform starter keeps workload identity federation as the preferred documented target, while the concrete provider resource may still need tenant-specific verification or a manual creation step depending on provider support.
- Private networking usually implies self-hosted agents or another network-aware execution path for pipeline jobs.
- Key Vault-linked variable groups require an Azure DevOps service connection ID. If that connection is created outside this Terraform stack, provide `existing_service_endpoint_id`.

## Suggested Execution Order

1. create Terraform backend and state location
2. define Azure-hosted Terraform inputs in Azure DevOps variables, variable groups, and Key Vault
3. run `terraform init`
4. run `terraform plan`
5. run `terraform apply`
6. verify Azure resources
7. verify Azure DevOps service connection, environments, and variable groups
8. move to ML delivery only after foundation is healthy

## Private Networking Notes

This starter now includes:

- a shared VNet
- a private endpoints subnet
- a self-hosted agents subnet
- private DNS zones for Blob, Key Vault, and ACR
- private endpoints for storage blob, Key Vault, and ACR

You will likely still want to extend this for a real enterprise landing zone with:

- NSGs
- route tables
- firewall rules
- hub/spoke design
- self-hosted agent compute

## Files

- [versions.tf](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/versions.tf)
- [providers.tf](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/providers.tf)
- [variables.tf](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/variables.tf)
- [main.tf](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/main.tf)
- [terraform.tfvars.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/terraform.tfvars.example)
