# Terraform Provisioning

This folder is the preferred production-grade provisioning path for this repo.

## Fresh Setup Or Existing Resources? Read This First

Terraform behaves differently depending on where your Azure resources came from:

| Situation | Covered? | What to do |
|-----------|----------|------------|
| Nothing exists yet (fresh tenant/subscription) | Yes | Run `bootstrap_backend.sh` once, set variables, then `terraform init/plan/apply`. Everything is created from zero. |
| Resources exist and are already in Terraform state | Yes | Normal operation. Re-runs are idempotent; plan shows no changes unless config changed. |
| Resources exist in Azure (or Azure DevOps) but are NOT in Terraform state | No — apply fails with `already exists` | Adopt them declaratively: `terraform apply -var 'bootstrap_adopt=["all"]'` (see `imports.tf`), or reference them with `data` sources, or disable creation with a feature flag. This is intentional Terraform behavior, not a bug. |

### Fresh setup quickstart

The operating principle: the pipeline provisions everything it possibly can.
The only manual work is "day 0" — the trust and identity objects that must
exist before any pipeline can run at all:

1. Create the Azure DevOps day-0 objects (Terraform cannot create the things
   it needs to authenticate with): project, PAT, service connection
   `az-mlops-sc` (whose identity needs subscription Contributor), variable
   group `aml-infra-tfvars` with the `TF_VAR_*` and `TF_BACKEND_*` values,
   and the secret pipeline variable `AZURE_DEVOPS_PAT`.
2. Create the pipeline from `azure-devops/azure-pipelines-infra.yml` and run it.

That is the whole fresh setup. The pipeline itself ensures the Terraform
state backend exists (it runs `bootstrap_backend.sh` idempotently before
`terraform init`), then plans and applies everything else. No laptop
execution is required.

Running locally (`az login`, `bash bootstrap_backend.sh`, `terraform plan`)
remains possible for development and debugging, but it is not the operating
path.

On a truly fresh subscription there is nothing to import and no
`already exists` error is possible.

### Existing-resource (brownfield) recovery

If a previous partial apply, a manual portal action, or another tool already
created some of the resources this config declares, Terraform must be told it
owns them before the next apply. Adoption is declarative and gated by the
`bootstrap_adopt` variable (see [imports.tf](imports.tf)):

```bash
terraform plan  -var 'bootstrap_adopt=["all"]'   # adoptions are shown in the plan
terraform apply -var 'bootstrap_adopt=["all"]'
```

Entries can also target a specific kind or environment, for example
`["storage", "app_insights:dev"]`. An entry whose resource does not actually
exist in Azure fails the plan with `Cannot import non-existent remote object` —
remove that entry and Terraform will create the resource normally. After the
adoption apply succeeds, drop the variable; subsequent runs need nothing.

Azure DevOps objects (environments, variable groups) have numeric import IDs
that require a REST lookup, so they are adopted with a helper script instead:
export `AZURE_DEVOPS_EXT_PAT` and run `bash import_azdo_bootstrap.sh`.

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

- Terraform `>= 1.7.0`

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

- `terraform version` shows a version `>= 1.7.0`

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

1. create Terraform backend and state location (`bash bootstrap_backend.sh`)
2. define Azure-hosted Terraform inputs in Azure DevOps variables, variable groups, and Key Vault
3. run `terraform init`
4. run `terraform plan`
5. run `terraform apply`
6. verify Azure resources
7. verify Azure DevOps service connection, environments, and variable groups
8. move to ML delivery only after foundation is healthy

## Remote Backend Is Required For Production

For production CI/CD, this Terraform must use persistent remote state.

Use Azure Storage-backed state with:

- dedicated resource group
- dedicated storage account
- dedicated blob container
- one explicit state key per platform stack

Example backend values for this tenant:

```text
TF_BACKEND_RESOURCE_GROUP=rg-usedcar-tfstate
TF_BACKEND_STORAGE_ACCOUNT=stusedcartfstate01
TF_BACKEND_CONTAINER=tfstate
TF_BACKEND_KEY=azureml-enterprise.tfstate
```

An example backend config file is provided at:

- [backend.hcl.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-mlops-repo/mlops-azure-azureml/infra/bicep/terraform/backend.hcl.example)

### Why This Matters

Without a remote backend:

- each pipeline run starts with fresh local state
- partial applies create orphaned Azure resources
- the next apply tries to recreate existing resources
- recovery becomes import-heavy and brittle

### Azure DevOps Variable Placement For Backend

Store these backend values in Azure DevOps variable group `aml-infra-tfvars`:

- `TF_BACKEND_RESOURCE_GROUP`
- `TF_BACKEND_STORAGE_ACCOUNT`
- `TF_BACKEND_CONTAINER`
- `TF_BACKEND_KEY`

They are configuration values, not secrets.

### Recovery After Partial Apply

If resources were created before remote backend was enabled:

1. enable the backend first
2. run `terraform init` against the backend
3. import already-created resources into state
4. rerun `terraform plan`
5. rerun `terraform apply`

The production mechanism for step 3 is the declarative, gated import blocks in
[imports.tf](imports.tf):

```bash
terraform plan  -var 'bootstrap_adopt=["all"]'   # review adoptions in the plan
terraform apply -var 'bootstrap_adopt=["all"]'
```

If only some resources exist (a genuinely partial apply), list exactly what
exists, at kind or kind:env granularity:

```bash
terraform apply -var 'bootstrap_adopt=["network_rg", "vnet", "storage", "app_insights:dev"]'
```

Behavior of the import blocks:

- default empty list: inert; fresh setups are completely unaffected
- target already in Terraform state: no-op, safe to leave enabled for one run
- target missing in Azure: plan fails with `Cannot import non-existent remote
  object` — remove that entry and Terraform will create the resource instead

This runs through the normal plan/apply path, so adoptions are visible in the
plan output, reviewable in a PR, and executable from the CI pipeline — no
laptop-only imperative steps.

Azure DevOps environments and variable groups are the one exception: their
Terraform import IDs are numeric and require a REST lookup, which import
blocks cannot express. For those, a small helper remains:

```bash
export AZURE_DEVOPS_EXT_PAT=<pat-with-env-and-vargroup-read>
bash import_azdo_bootstrap.sh
terraform plan
```

Why this is production-correct:

- we keep Terraform as the long-term owner
- we recover state instead of deleting partially created enterprise resources
- we avoid adding brittle "skip if exists" logic that would hide ownership drift

## Why Terraform Does Not "Skip If Exists"

Terraform is state-driven, not existence-driven.

That means:

- if a resource block exists in code and the object is already in Terraform state, Terraform manages it
- if a resource block exists in code and the object exists only in Azure but not in Terraform state, Terraform tries to create it
- Azure then returns `already exists`
- the production-grade recovery action is to import it

If a resource should exist but must not be managed by Terraform, the production approach is:

- do not declare it as a `resource`
- use a `data` source instead
- or gate creation with explicit feature flags

Do not rely on Terraform to dynamically "notice" an existing resource and silently skip ownership.

## Managing Multiple Resources Of The Same Type In Production

For production Terraform, multiple similar resources are normally handled with:

- `for_each` for stable keyed resources
- `count` for simple indexed repetition
- modules for repeated architecture patterns

This repo already uses `for_each` for environment-scoped resources, for example:

- `dev`
- `test`
- `prod`

This is the preferred production pattern because each instance has a stable address in Terraform state.

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

- [versions.tf](/Users/amit/Desktop/Code 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-mlops-repo/mlops-azure-azureml/infra/bicep/terraform/versions.tf)
- [providers.tf](/Users/amit/Desktop/Code 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-mlops-repo/mlops-azure-azureml/infra/bicep/terraform/providers.tf)
- [variables.tf](/Users/amit/Desktop/Code 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-mlops-repo/mlops-azure-azureml/infra/bicep/terraform/variables.tf)
- [main.tf](/Users/amit/Desktop/Code 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-mlops-repo/mlops-azure-azureml/infra/bicep/terraform/main.tf)
- [terraform.tfvars.example](/Users/amit/Desktop/Code 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-mlops-repo/mlops-azure-azureml/infra/bicep/terraform/terraform.tfvars.example)
