# Azure DevOps Pipelines

This folder contains the enterprise-first CI/CD entrypoints for the Azure ML platform and model lifecycle.

## Pipeline Split

### `azure-pipelines-infra.yml`

Dedicated Terraform infrastructure pipeline for:

- `terraform fmt -check`
- `terraform init`
- `terraform validate`
- `terraform plan`
- approval-gated `terraform apply`

### `azure-pipelines.yml`

Primary multi-stage pipeline for:

- validation
- AML training submission
- registry promotion
- test deployment
- prod deployment
- monitoring config generation

### `azure-pipelines-monitoring.yml`

Separate scheduled monitoring-oriented pipeline for:

- generating production monitoring policy artifacts
- integrating with a broader monitor/retrain workflow

## Recommended Azure DevOps Setup

Use:

- GitHub as the source repository
- Azure DevOps pipeline YAML from this folder
- Azure Key Vault for secret storage
- Azure DevOps variable groups for non-secret Terraform inputs
- Azure DevOps secret variable or Key Vault-backed variable for `AZURE_DEVOPS_PAT` during Terraform bootstrap to the Azure DevOps provider
- Azure Resource Manager service connection for Azure authentication during Terraform execution
- Azure DevOps Environments for `aml-test-approval`, `aml-test`, and `aml-prod`
- Azure DevOps Environment `aml-platform-infra` for approval-gated Terraform apply
- Variable groups backed by Azure Key Vault for non-code secrets

## Initial Azure DevOps Bootstrap

Before the infrastructure pipeline can run successfully, create these Azure DevOps bootstrap objects:

1. GitHub-backed pipeline using:
   - `azure-devops/azure-pipelines-infra.yml`
2. Azure Resource Manager service connection:
   - `az-mlops-sc`
3. Library variable group:
   - `aml-infra-tfvars`
4. Pipeline secret variable:
   - `AZURE_DEVOPS_PAT`
5. Environment:
   - `aml-platform-infra`

The pipeline will not work end to end until all five exist.

## Recommended Execution Order

1. run `azure-pipelines-infra.yml` to provision or update platform resources
2. verify Terraform apply succeeded
3. run `azure-pipelines.yml` for AML training, promotion, deployment, and monitoring

The ML pipeline should not be the first place where platform provisioning is attempted.

## Required Variables

Pipeline variables or variable groups should provide:

- `AZURE_DEVOPS_PAT` as a secret variable or Key Vault-backed secret for the Terraform infra pipeline
- non-secret Terraform inputs as pipeline variables or variable-group variables using `TF_VAR_...` names
- `WORKSPACE_MODEL_VERSION`
- `REGISTRY_MODEL_VERSION`
- optional environment-specific overrides

## Terraform Input Pattern

For production CI/CD, do not depend on a developer-local `terraform.tfvars` file.

Recommended pattern:

1. store secrets in Azure Key Vault
2. expose secrets to Azure DevOps through a Key Vault-backed variable group or secret pipeline variables
3. expose non-secret Terraform inputs through Azure DevOps variables or variable groups using `TF_VAR_...` names
4. let the Terraform pipeline consume those environment variables directly

Examples of non-secret Terraform inputs to define in Azure DevOps:

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

Examples of secret Terraform inputs to source from Key Vault:

- `AZURE_DEVOPS_PAT`
- `TF_VAR_service_principal_key` if secret-based auth is still used

## Where To Add Them In Azure DevOps

Use two different Azure DevOps locations:

1. `Pipelines -> Library -> Variable groups`
   Use this for non-secret Terraform inputs such as:
   - `TF_VAR_subscription_id`
   - `TF_VAR_location`
   - `TF_VAR_prefix`
   - `TF_VAR_azure_devops_project_name`

2. `Pipeline -> Edit -> Variables`
   Use this for direct pipeline variables and secrets such as:
   - `AZURE_DEVOPS_PAT`

Important:

- `aml-infra-tfvars` is a Library variable group
- it is not added from the `New variable` popup
- this repo's infrastructure pipeline references it directly in YAML
- the infrastructure pipeline also requires a bootstrap Azure service connection referenced by `bootstrapAzureServiceConnection`
- the default placeholder in YAML is `az-mlops-sc`, but you should align it to your real bootstrap service connection name

## How To Create `az-mlops-sc`

In Azure DevOps:

1. go to `Project settings -> Service connections`
2. click `New service connection`
3. choose `Azure Resource Manager`
4. choose:
   - `Identity type`: `App registration (automatic)`
   - `Credential`: `Workload identity federation`
   - `Scope level`: `Subscription`
5. select subscription:
   - `DemoPay`
6. choose resource group:
   - `All resource groups` is acceptable for bootstrap
   - or narrow it later after platform stabilization
7. set `Service connection name`:
   - `az-mlops-sc`
8. save

If the dialog does not let you save, the most common reasons are:

- the bottom of the modal is off-screen and the `Save` button is below the fold
- Azure DevOps has not finished validating the subscription context yet
- a required field still has focus or has not validated
- your account lacks permission to create service connections in the project

Practical fix:

- scroll to the very bottom of the modal
- wait a few seconds after selecting subscription and resource-group scope
- confirm the exact name is `az-mlops-sc`
- if still blocked, verify your Azure DevOps project permissions for service connection creation

## CLI Fallback If The UI Save Button Does Nothing

If the Azure DevOps UI refuses to save the Azure Resource Manager service connection even after trying a new browser, the most reliable fallback is:

1. create a dedicated bootstrap service principal in Azure
2. create the Azure DevOps service connection from CLI using that service principal
3. use that service connection for the Terraform bootstrap pipeline
4. keep workload identity federation as the target end-state for longer-term hardening

Important:

- the Azure DevOps CLI path currently supports a secret-based Azure RM bootstrap connection
- this is acceptable as a bootstrap path when the portal WIF flow is blocked
- once the tenant-side UI issue is resolved, you can replace the bootstrap connection with a workload identity federation connection

### Why This Was Needed

This repo was designed with workload identity federation as the preferred Azure DevOps-to-Azure authentication model.

However, in this tenant the Azure DevOps portal flow for creating the WIF-based Azure Resource Manager service connection was not saving successfully.

Because of that, we needed a temporary bootstrap path that could:

- authenticate Azure DevOps to Azure
- let the Terraform infra pipeline run
- avoid blocking the whole enterprise setup on a portal bug or tenant-side UI issue

That is why we created a dedicated bootstrap service principal and used Azure DevOps CLI to create `az-mlops-sc`.

### What `az ad sp create-for-rbac` Actually Did

This command:

```bash
az ad sp create-for-rbac \
  --name usedcar-ado-bootstrap-sp \
  --role Contributor \
  --scopes /subscriptions/5c6c4978-12d9-43e0-8ba4-9fb538eb1e64
```

did all of the following:

1. created an Entra application
2. created the corresponding service principal
3. generated a client secret
4. assigned Azure RBAC `Contributor` on the `DemoPay` subscription

Why we needed that:

- the Azure DevOps CLI command for Azure RM service connections needs a service principal
- the portal WIF flow was blocked
- therefore we needed a bootstrap identity that Azure DevOps could use immediately

### Are We Using WIF Right Now?

Not for the bootstrap Azure service connection.

Current temporary reality:

- `az-mlops-sc` is a bootstrap Azure RM service connection backed by a service principal secret

Target end-state:

- replace `az-mlops-sc` with a WIF-based Azure service connection once the portal or tenant flow is working correctly

So the architecture still prefers WIF, but the current bootstrap implementation is temporarily secret-based.

### Bootstrap Pattern

Create a dedicated bootstrap app registration and service principal with subscription scope:

```bash
az ad sp create-for-rbac \
  --name usedcar-ado-bootstrap-sp \
  --role Contributor \
  --scopes /subscriptions/5c6c4978-12d9-43e0-8ba4-9fb538eb1e64
```

Capture these values from the output:

- `appId`
- `password`
- `tenant`

Then export the PAT only in your current shell:

```bash
export AZURE_DEVOPS_EXT_PAT="<fresh-azure-devops-pat>"
export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY="<service-principal-secret>"
```

Create the Azure DevOps service connection:

```bash
az devops service-endpoint azurerm create \
  --organization "https://dev.azure.com/genaidevops0" \
  --project "mlops1" \
  --azure-rm-service-principal-id "<appId>" \
  --azure-rm-subscription-id "5c6c4978-12d9-43e0-8ba4-9fb538eb1e64" \
  --azure-rm-subscription-name "DemoPay" \
  --azure-rm-tenant-id "b6cb2304-83e3-47be-8adb-f6bb37058d52" \
  --name "az-mlops-sc"
```

Verify it exists:

```bash
az devops service-endpoint list \
  --organization "https://dev.azure.com/genaidevops0" \
  --project "mlops1" \
  --query "[].{name:name,id:id,type:type}" \
  -o table
```

Then capture the service connection ID:

```bash
az devops service-endpoint list \
  --organization "https://dev.azure.com/genaidevops0" \
  --project "mlops1" \
  --query "[?name=='az-mlops-sc'].id | [0]" \
  -o tsv
```

Use that value as:

- pipeline bootstrap service connection name: `az-mlops-sc`
- Terraform input `TF_VAR_existing_service_endpoint_id`

### After Creating The Bootstrap Connection

Make sure Azure DevOps has:

1. pipeline variable group `aml-infra-tfvars`
2. pipeline secret variable `AZURE_DEVOPS_PAT`
3. `TF_VAR_existing_service_endpoint_id` set to the real service connection ID

The infrastructure pipeline can then:

- authenticate to Azure through `az-mlops-sc`
- authenticate to Azure DevOps through `AZURE_DEVOPS_PAT`
- avoid depending on a local `terraform.tfvars` file

## Production Notes

- Infra provisioning is intentionally its own stage and should also be runnable independently.
- Prod deployment should remain environment approval-gated.
- Replace placeholder variable names and service connection names with your organization standards.
