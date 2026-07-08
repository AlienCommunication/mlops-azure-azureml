# Azure DevOps Operating Model

Use GitHub for source control and Azure DevOps for enterprise CI/CD orchestration.

GitHub Actions is retained only for lightweight repository CI validation. Model delivery and infrastructure delivery should run through Azure DevOps.

## Recommended Pipelines

### Terraform Infrastructure Pipeline

Use [azure-pipelines-infra.yml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/azure-pipelines-infra.yml) for:

- Terraform formatting check
- Terraform validation
- Terraform plan
- approval-gated Terraform apply

This is the normal production path for infrastructure changes after bootstrap.

### Primary Multi-Stage Pipeline

Use [azure-pipelines.yml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/azure-pipelines.yml) for:

- validation
- AML training submission
- registry promotion
- test deployment
- prod deployment

### Monitoring Pipeline

Use [azure-pipelines-monitoring.yml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/azure-pipelines-monitoring.yml) for scheduled monitoring-related tasks.

## Environments

Create Azure DevOps Environments:

- `aml-platform-infra`
- `aml-test-approval`
- `aml-test`
- `aml-prod`

Use approval gates on:

- `aml-platform-infra`
- `aml-test-approval`
- `aml-prod`

## Bootstrap Service Connection

Create an Azure Resource Manager service connection for the infrastructure pipeline:

- name: `az-mlops-sc`
- recommended auth: `Workload identity federation`
- recommended scope: `Subscription`
- current tenant subscription: `DemoPay`

This service connection is used so Azure DevOps can authenticate to Azure before Terraform runs.

## GitHub Integration

The repo remains in GitHub, while Azure DevOps:

- checks out the GitHub source
- runs the YAML pipeline
- uses service connections for Azure access

## Variables

Use variable groups for:

- environment-specific non-secret values
- Key Vault-backed secrets
- model version handoff if your process requires explicit version selection

Use a secret pipeline variable for:

- `AZURE_DEVOPS_PAT` in the Terraform infra pipeline until the Azure DevOps bootstrap mechanism is replaced with a less manual pattern

## Operating Sequence

1. run the Terraform infra pipeline first
2. verify the platform foundation exists
3. run the ML delivery pipeline
4. use Azure DevOps environment approvals before apply and prod deployment

## GitHub Actions Scope

Keep GitHub Actions only for repository CI such as:

- dependency installation validation
- local smoke validation
- fast pull request feedback

Do not use GitHub Actions as the primary production CD path for:

- infrastructure apply
- AML training promotion flow
- test deployment
- prod deployment
