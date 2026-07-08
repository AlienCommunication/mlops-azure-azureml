# Provisioning Infrastructure

This document defines the production-grade provisioning boundary for this project.

## Core Principle

There are two separate provisioning domains:

1. `Azure resource provisioning`
   This includes Azure resources such as:
   - resource groups
   - Azure ML workspaces
   - Azure ML registry
   - storage accounts / ADLS
   - Key Vault
   - ACR
   - Log Analytics
   - Application Insights
   - networking and private endpoints

2. `Azure DevOps provisioning`
   This includes Azure DevOps resources such as:
   - service connections
   - environments
   - variable groups
   - approvals and checks
   - pipeline permissions

These are different control planes, so they should not be treated as one thing.

## Can Terraform Provision Everything

Yes, Terraform can be the preferred single IaC tool for this setup.

That is often a better production story because:

- Azure resources can be provisioned with `azurerm` and `azapi`
- Azure DevOps resources can be provisioned with the `azuredevops` provider
- one tool can manage both planes, even though the planes are still logically separate

For this repo, Terraform is now the preferred production direction.

## What Should Be Provisioned With Terraform

Use Terraform for both:

- Azure resources
- Azure DevOps resources

In this repo, Terraform is intended to manage:

- resource groups
- AML workspaces
- shared AML registry
- storage
- Key Vault
- ACR
- Log Analytics
- Application Insights
- Azure DevOps service connections
- Azure DevOps environments
- Azure DevOps variable groups
- Key Vault-linked variable groups

## What Bicep Is Now

Bicep remains in the repo as:

- a starter Azure-only reference
- a fallback or comparison path
- a useful option for teams already standardized on ARM/Bicep

But the preferred production direction is Terraform-first.

## What Bicep Still Cannot Provision

Do not expect Bicep to create:

- Azure DevOps service connections
- Azure DevOps environments
- Azure DevOps variable groups
- Azure DevOps approvals

Why:

- these are Azure DevOps resources, not Azure Resource Manager resources
- Bicep does not manage Azure DevOps objects

## Production-Grade Recommendation

Preferred model:

- `Terraform` for Azure resources
- `Terraform` for Azure DevOps resources

Fallback model:

- `Bicep` for Azure resources
- `Terraform` for Azure DevOps resources

The repo now includes a Terraform-first foundation under:

- [infra/terraform](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform)

## What Terraform Would Manage Here

If you want full production-grade IaC coverage, Terraform should manage:

- Azure DevOps project references if needed
- Azure Resource Manager service connection
- Azure DevOps environments:
  - `aml-test-approval`
  - `aml-test`
  - `aml-prod`
- variable groups
- variable group to Key Vault links
- environment approvals and checks where supported by provider/workflow
- pipeline authorizations and permissions where required

## Identity Model For Terraform-First Provisioning

For this repo, the clean target model is:

- Terraform authenticates to Azure DevOps using a PAT for bootstrap/provider access
- Azure DevOps pipelines authenticate to Azure using workload identity federation

That means:

- PAT is used to create or manage Azure DevOps-side objects
- WIF is used when pipeline jobs actually deploy or operate on Azure

This is a practical and production-aligned split.

## Private Networking From Day 1

Private networking means Azure ML and its dependent services are not exposed only through broad public access paths.

The usual Azure services involved are:

- Virtual Network (VNet)
- Subnets
- Private Endpoints
- Private DNS Zones
- Azure ML workspace managed network features
- Storage account network rules
- Key Vault network rules
- Container Registry network rules

### What gets privatized

Typically:

- Azure ML workspace dependencies
- storage account
- Key Vault
- ACR
- sometimes Log Analytics ingestion patterns depending on organization standards

### How it works

1. You create a VNet and subnets.
2. You create private endpoints for services like storage, Key Vault, and AML dependencies.
3. Private DNS zones resolve those services to private IPs.
4. Allowed clients and compute access them over the VNet instead of broad public endpoints.
5. Public network access is reduced or disabled according to policy.

### Why teams use it

- tighter network isolation
- reduced public exposure
- better alignment with enterprise security policy
- easier enforcement of controlled egress/ingress

### What changes operationally

Private networking increases setup complexity:

- DNS must resolve correctly
- pipeline agents may need network reachability
- AML compute must reach storage, Key Vault, ACR, and control plane dependencies
- Azure DevOps-hosted agents may not be enough if the environment is fully private

### Common production consequence

If you choose private networking from day 1, you often also need:

- self-hosted Azure DevOps agents inside the network, or
- a carefully designed access pattern that still allows the pipeline execution path to reach required private resources

This is why public access is often used for first verification and private networking is then tightened. If your policy requires private networking from day 1, we should encode VNet, subnet, private endpoint, DNS, and likely self-hosted agent assumptions into the infrastructure design.

For this tenant, the chosen direction is:

- private networking from day 1
- self-hosted Azure DevOps agents
- private endpoints for storage, Key Vault, and ACR
- Azure DevOps pipeline auth to Azure through workload identity federation
- Terraform bootstrap to Azure DevOps through PAT

## Recommended Provisioning Sequence

### Actual Bootstrap Sequence Used In This Tenant

The setup path used here was:

1. verify Azure subscription login with Azure CLI
2. upgrade Terraform to a supported version
3. create Azure DevOps project and connect the GitHub repo
4. create the Azure DevOps infra pipeline from `azure-devops/azure-pipelines-infra.yml`
5. create variable group `aml-infra-tfvars`
6. add non-secret Terraform inputs to the variable group
7. attempt to create WIF-based Azure service connection in Azure DevOps UI
8. fall back to CLI bootstrap because the UI save flow was blocked
9. create bootstrap service principal in Azure with `az ad sp create-for-rbac`
10. create Azure RM service connection `az-mlops-sc` from Azure DevOps CLI
11. capture service connection ID `ac870ddd-2ef3-4522-9ad2-7c937c2390f4`
12. add `TF_VAR_existing_service_endpoint_id` to `aml-infra-tfvars`
13. add secret pipeline variable `AZURE_DEVOPS_PAT`
14. rerun the infra pipeline

This sequence is now the documented tenant-tested bootstrap path for this repo.

## Bootstrap Hardening Notes From First Real Apply

The first real Terraform apply in this tenant surfaced three important platform constraints:

1. Azure Container Registry with `public_network_access_enabled = false` requires `Premium` SKU
2. Azure ML registry creation should be attached to a resource group scope in this Terraform implementation
3. Azure DevOps Key Vault-linked variable groups should not be created during the earliest bootstrap run unless:
   - the service connection already has Key Vault RBAC
   - the vault secrets that should be linked actually exist

Because of that, the safer bootstrap pattern is:

- keep private networking enabled
- let Terraform create `Premium` ACR when private networking is enabled
- create a shared resource group for the AML registry
- defer Key Vault-linked variable groups until a later hardening pass

For this reason, set:

```text
TF_VAR_enable_key_vault_linked_variable_groups=false
```

during bootstrap.

## State Management Lesson From Real Pipeline Runs

The early Azure DevOps pipeline runs in this tenant exposed a critical production gap:

- Terraform was running without a remote backend
- a failed `apply` created some Azure resources successfully
- the next pipeline run started with fresh local state
- Terraform then tried to create the same Azure resources again
- Azure returned `already exists` errors and Terraform asked for import

This is not an Azure bug.
It is the expected behavior when CI/CD runs Terraform without persistent shared state.

### What This Means

Without a remote backend:

- every pipeline run behaves like a fresh Terraform client
- partial apply recovery is painful
- import and drift correction become manual
- the setup is not yet production-grade

### Production-Correct Fix

Before continuing repeated infra applies, the platform should use a remote backend, typically Azure Storage with:

- a dedicated Terraform state resource group
- a dedicated storage account
- a blob container for state
- an explicit state key

Then all pipeline runs use the same persisted state.

### Short-Term Recovery Choices

If resources were partially created before the backend was added, you have two choices:

1. import the already-created resources into Terraform state
2. delete the partially-created resources and rerun after backend is fixed

For production hygiene, backend-first plus import is usually the better route if you want to preserve the created assets.

### Backend Values Recommended For This Tenant

Use backend configuration like:

```text
TF_BACKEND_RESOURCE_GROUP=rg-usedcar-tfstate
TF_BACKEND_STORAGE_ACCOUNT=stusedcartfstate01
TF_BACKEND_CONTAINER=tfstate
TF_BACKEND_KEY=azureml-enterprise.tfstate
```

These should be added to Azure DevOps variable group `aml-infra-tfvars`.

## Local Bootstrap Gate

Before any provisioning work, verify the local Terraform runtime:

```bash
terraform version
```

This repo requires Terraform `>= 1.6.0`.

If your Mac still shows `Terraform v1.5.7`, fix the local toolchain first:

```bash
brew install tfenv
brew unlink terraform
brew link tfenv
tfenv install 1.9.8
tfenv use 1.9.8
terraform version
```

Do not run `terraform init` until this version check succeeds.

### Phase 1: Foundation Provisioning

Run first:

1. run the Terraform infra CI/CD pipeline
2. provision Azure resources with Terraform
3. provision Azure DevOps resources with Terraform
4. verify AML workspaces, registry, storage, Key Vault, service connection, environments, and variable groups exist

Recommended production path:

- use [azure-pipelines-infra.yml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/azure-pipelines-infra.yml) for normal `plan` and `apply`
- keep local Terraform execution for bootstrap validation and break-glass debugging only

### Phase 2: ML Delivery

Only after Phases 1 and 2:

1. submit AML training pipeline
2. register model
3. promote model to registry
4. deploy to test
5. deploy to prod
6. configure monitoring and retraining

## Minimum Manual Setup If Terraform Is Not Yet Used For Azure DevOps

If you are not yet applying the Terraform DevOps layer, do this manually in Azure DevOps:

1. create service connection `az-mlops-sc`
2. create environments:
   - `aml-test-approval`
   - `aml-test`
   - `aml-prod`
3. create variable groups:
   - `aml-dev-shared`
   - `aml-test-shared`
   - `aml-prod-shared`
4. link variable groups to Key Vault where appropriate
5. add approval checks to:
   - `aml-test-approval`
   - `aml-prod`

## If Azure DevOps UI Cannot Save The Azure Service Connection

In some tenants, the Azure DevOps portal may let you fill the Azure Resource Manager service connection form but silently fail when `Save` is clicked.

When that happens, use a CLI bootstrap path:

1. create a dedicated bootstrap service principal in Azure
2. create the Azure DevOps ARM service connection from CLI
3. store the resulting service connection ID in Azure DevOps as `TF_VAR_existing_service_endpoint_id`
4. run the infrastructure pipeline again

Why this is acceptable:

- this is a bootstrap workaround for a blocked tenant/UI flow
- it unblocks infra provisioning without changing the overall enterprise architecture
- the intended long-term model is still workload identity federation for Azure DevOps-to-Azure auth

Recommended bootstrap commands:

```bash
az ad sp create-for-rbac \
  --name usedcar-ado-bootstrap-sp \
  --role Contributor \
  --scopes /subscriptions/5c6c4978-12d9-43e0-8ba4-9fb538eb1e64
```

Then:

```bash
export AZURE_DEVOPS_EXT_PAT="<fresh-azure-devops-pat>"
export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY="<service-principal-secret>"

az devops service-endpoint azurerm create \
  --organization "https://dev.azure.com/genaidevops0" \
  --project "mlops1" \
  --azure-rm-service-principal-id "<appId>" \
  --azure-rm-subscription-id "5c6c4978-12d9-43e0-8ba4-9fb538eb1e64" \
  --azure-rm-subscription-name "DemoPay" \
  --azure-rm-tenant-id "b6cb2304-83e3-47be-8adb-f6bb37058d52" \
  --name "az-mlops-sc"
```

Then fetch the service connection ID:

```bash
az devops service-endpoint list \
  --organization "https://dev.azure.com/genaidevops0" \
  --project "mlops1" \
  --query "[?name=='az-mlops-sc'].id | [0]" \
  -o tsv
```

Use that ID in the Azure DevOps variable group as:

```text
TF_VAR_existing_service_endpoint_id=<service-connection-id>
```

This repo now treats that service connection as the bootstrap Azure identity for the Terraform infra pipeline.

## Key Vault Ownership

Key Vault itself is an Azure resource, so it should be provisioned by Terraform for the preferred production path.

The Azure DevOps link to Key Vault is not an Azure resource, so that should be:

- codified using Terraform where supported, or
- created manually in Azure DevOps if provider behavior in your tenant requires it

## Production Decision For This Repo

For this repo, the intended production model is now:

- preferred: Terraform-first for both Azure and Azure DevOps
- fallback: Bicep for Azure plus Terraform or manual setup for Azure DevOps

That gives the cleanest enterprise story while still keeping the older Azure-only path available.
