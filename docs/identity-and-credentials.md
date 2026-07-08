# Identity And Credentials Strategy

This project should not use developer-local secrets as the primary enterprise operating path.

## Recommended Identity Model

### CI/CD Identity

Use Azure DevOps service connections with one of these patterns:

1. workload identity federation
2. service principal with certificate
3. service principal with secret only if the first two are not available

Preferred order is exactly as listed above.

## Current State In This Repo

There are two separate ideas in this setup:

1. `target-state production identity model`
2. `bootstrap identity used to get the platform unstuck`

Target state:

- Azure DevOps should use workload identity federation for Azure access
- Azure ML resources should use managed identities where possible
- Azure DevOps PAT usage should be limited to Terraform bootstrap for Azure DevOps object management

Bootstrap state used in this tenant:

- the Azure DevOps portal would not save the WIF-based Azure Resource Manager service connection
- because of that UI blocker, a temporary Azure service principal was created in Azure
- that service principal is used only to create a bootstrap Azure RM service connection named `az-mlops-sc`
- this is a temporary workaround, not the long-term preferred identity pattern

So yes: at this exact bootstrap stage, the Azure service connection is temporarily not using WIF.

That does not mean the architecture abandoned WIF.
It means we are using a secret-based bootstrap connection because the Azure DevOps UI path for WIF was blocked in this tenant.

## Why We Ran `az ad sp create-for-rbac`

We ran:

```bash
az ad sp create-for-rbac \
  --name usedcar-ado-bootstrap-sp \
  --role Contributor \
  --scopes /subscriptions/5c6c4978-12d9-43e0-8ba4-9fb538eb1e64
```

Why:

- Azure DevOps needed an Azure identity it could use for the infrastructure pipeline
- the intended WIF-based service connection could not be created from the portal because the `Save` flow was failing
- the Azure DevOps CLI fallback for Azure RM service connections expects a service principal
- this command creates that bootstrap service principal and assigns it Azure RBAC on the subscription

What each part means:

- `az ad sp create-for-rbac`
  Creates an Entra application/service principal and also assigns an Azure RBAC role.
- `--name usedcar-ado-bootstrap-sp`
  Human-readable identity name for the bootstrap Azure DevOps connection.
- `--role Contributor`
  Grants the identity permission to create and update most Azure resources in scope.
- `--scopes /subscriptions/5c6c4978-12d9-43e0-8ba4-9fb538eb1e64`
  Limits the RBAC assignment to the `DemoPay` subscription instead of all subscriptions.

What the output values mean:

- `appId`
  The client ID of the Entra application. Azure DevOps uses this to identify the service principal.
- `password`
  The client secret. Azure DevOps CLI uses this to create the bootstrap Azure RM service connection.
- `tenant`
  The Microsoft Entra tenant ID where the application lives.
- `displayName`
  The friendly name of the identity.

Important:

- the client secret is sensitive
- if it has been pasted in chat or stored in shell history, rotate it before production use
- do not commit it to the repo

## What This Bootstrap Service Principal Is For

This bootstrap service principal is not the model-serving identity.
It is not the AML training identity.
It is not the online endpoint managed identity.

It is only for:

- Azure DevOps infrastructure pipeline access to Azure
- creation and update of Azure platform resources during Terraform bootstrap

## What It Is Not For

Do not use this bootstrap service principal for:

- application runtime access
- inference requests
- model endpoint code
- training code inside AML jobs
- long-term production identity if WIF can be enabled

## Migration Goal Back To WIF

The preferred end-state remains:

1. create a workload identity federation Azure Resource Manager service connection in Azure DevOps
2. update pipeline references so Azure DevOps uses that WIF service connection for Azure access
3. verify infra and ML pipelines still run correctly
4. remove the bootstrap secret-based service connection
5. delete or disable the bootstrap service principal

In short:

- `now`: secret-based bootstrap service connection because tenant UI is blocked
- `target`: WIF-based Azure DevOps service connection

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

## Terraform Input Strategy In CI/CD

For enterprise CI/CD, split Terraform inputs into two classes:

1. `Secret inputs`
   Store in Azure Key Vault and surface into Azure DevOps through Key Vault-backed variable groups or secret pipeline variables.

2. `Non-secret inputs`
   Store in Azure DevOps variable groups or pipeline variables using Terraform environment-variable naming like `TF_VAR_subscription_id`.

Recommended examples:

- Key Vault backed:
  - `AZURE_DEVOPS_PAT`
  - `TF_VAR_service_principal_key` if still used

- Azure DevOps non-secret variables:
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

Avoid making the CI/CD pipeline depend on a developer-local `terraform.tfvars` file.

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
