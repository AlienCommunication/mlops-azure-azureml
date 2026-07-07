# Infrastructure Guidance

This folder is for environment provisioning.

Read [provisioning-infra.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/provisioning-infra.md) first. It explains the production boundary between:

- Azure resource provisioning
- Azure DevOps provisioning

For the preferred production path, start with:

- [infra/terraform/README.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/README.md)

The exact Azure resources usually include:

- `rg-aml-dev`, `rg-aml-test`, `rg-aml-prod`
- `aml-ws-dev`, `aml-ws-test`, `aml-ws-prod`
- shared Azure ML registry
- storage accounts / ADLS
- Key Vault
- Azure Container Registry
- Log Analytics workspace
- Application Insights
- optional VNet and private endpoints

Recommended next step:

- start from the included `terraform/` foundation for the primary production path
- use `bicep/` only if your platform prefers Azure-only ARM provisioning for now
- make naming and tags match your landing zone conventions
