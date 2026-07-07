# Identity And Credentials Strategy

This project should not use developer-local secrets as the primary enterprise operating path.

## Recommended Identity Model

### CI/CD Identity

Use Azure DevOps service connections with one of these patterns:

1. workload identity federation
2. service principal with certificate
3. service principal with secret only if the first two are not available

Preferred order is exactly as listed above.

### Important Distinction: PAT vs Azure Service Connection Auth

Two different credentials can exist in this setup:

1. `Azure DevOps PAT`
   Used by Terraform only to manage Azure DevOps objects such as:
   - environments
   - variable groups
   - service connection definitions

2. `Azure service connection auth`
   Used by Azure DevOps pipelines to access Azure resources such as:
   - resource groups
   - Azure ML workspaces
   - storage
   - Key Vault

For a production-grade setup:

- using a PAT temporarily for Terraform bootstrap is acceptable
- using workload identity federation for the Azure service connection is preferred

Do not confuse these two. The PAT is not the Azure runtime auth model.

## Recommended PAT Handling For Terraform Bootstrap

If Terraform needs an Azure DevOps PAT:

- store it in Azure Key Vault
- retrieve it just before running Terraform
- pass it through `TF_VAR_azure_devops_pat`

Recommended pattern:

```bash
export TF_VAR_azure_devops_pat="$(az keyvault secret show \
  --vault-name <your-keyvault-name> \
  --name azure-devops-pat \
  --query value -o tsv)"
```

## Recommended Azure DevOps PAT Scopes

For this Terraform bootstrap path, the PAT should be created in the same Azure DevOps organization and should have enough scope for:

- `Project and Team (Read)`
- `Build (Read)`
- `Release (Read)` if your org still uses classic release features
- `Service Connections (Read, query, and manage)`
- `Variable Groups / Library (Read, create, and manage)`
- `Environment (Read, manage)`

If you want the quickest first validation, create a short-lived PAT with broad enough project administration rights for the bootstrap, verify Terraform end to end, then reduce scope afterward.

## Azure DevOps Authorization Troubleshooting

If Terraform fails with:

```text
You are not authorized to access Azure DevOps Organization
```

check these in order:

1. confirm `azure_devops_org_service_url` exactly matches your org URL
2. confirm the PAT was created inside that same Azure DevOps organization
3. confirm the PAT is not expired or revoked
4. confirm the PAT has scopes for environments, variable groups, and service connections
5. confirm the user who created the PAT has access to the target project
6. if you rotated the PAT, re-export `TF_VAR_azure_devops_pat` in the current shell

Useful reminder:

- Azure authentication can be correct while Azure DevOps authentication still fails
- this error is about the Azure DevOps provider, not your Azure subscription login

Avoid:

- storing PAT in `terraform.tfvars`
- committing PAT to the repo
- keeping PAT in long-lived plaintext files

## How To Store The PAT In Azure Key Vault

### Azure CLI

```bash
az keyvault secret set \
  --vault-name <your-keyvault-name> \
  --name azure-devops-pat \
  --value "<your-pat>"
```

### Azure Portal

1. Open Azure Portal.
2. Go to the Key Vault you want to use.
3. Open `Secrets`.
4. Click `Generate/Import`.
5. Use the secret name `azure-devops-pat`.
6. Paste the PAT value.
7. Save.

## Runtime Identity

### Azure ML Training Compute

Use managed identity for:

- reading training data from storage
- reading secrets from Key Vault
- writing artifacts to AML-managed storage

### Online Endpoints

Use managed identity for:

- accessing dependent Azure resources
- pulling configuration or secrets from Key Vault

## Secret Storage

Store secrets in Azure Key Vault, not in:

- repo files
- pipeline YAML
- developer shell history

Use Azure DevOps variable groups linked to Key Vault for:

- non-interactive deployment secrets
- external system credentials
- alerting webhooks if required

## Environment Separation

Keep separate:

- `dev` identities
- `test` identities
- `prod` identities

Apply least privilege on:

- subscription
- resource group
- AML workspace
- registry
- storage
- Key Vault

## What Should Not Be Secret

These are configuration values, not secrets:

- subscription ID
- resource group name
- workspace name
- registry name
- endpoint name

They can remain in environment config files.
