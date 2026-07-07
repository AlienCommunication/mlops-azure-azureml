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
