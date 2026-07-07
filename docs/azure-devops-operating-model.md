# Azure DevOps Operating Model

Use GitHub for source control and Azure DevOps for enterprise CI/CD orchestration.

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

- `aml-test-approval`
- `aml-test`
- `aml-prod`

Use approval gates on:

- `aml-test-approval`
- `aml-prod`

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
