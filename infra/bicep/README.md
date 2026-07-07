# Bicep Infrastructure

This folder contains a starter Azure-native layout for:

- `dev`, `test`, and `prod` resource groups
- one Azure ML workspace per environment
- storage account, Key Vault, ACR, Log Analytics, and Application Insights per environment
- optional shared Azure ML registry

Important boundary:

- Bicep provisions Azure resources
- Bicep does not provision Azure DevOps service connections, environments, or variable groups

For the production provisioning model, see [provisioning-infra.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/provisioning-infra.md).

If you want one IaC tool across Azure and Azure DevOps, use the Terraform path instead:

- [infra/terraform/README.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/README.md)

## Deploy

```bash
az deployment sub create \
  --location eastus \
  --template-file azure-mlops/infra/bicep/main.bicep \
  --parameters @azure-mlops/infra/bicep/parameters/dev.parameters.json
```

Repeat for `test` and `prod`.

## Notes

- This is a platform starter, not a full enterprise landing zone.
- For production, you will usually add private endpoints, customer-managed keys, diagnostic settings, and policy assignments.
- Terraform is now the preferred production path when you want one IaC model across Azure and Azure DevOps.
