# Azure ML Enterprise MLOps Blueprint

This project is a production-oriented Azure Machine Learning SDK v2 blueprint for a used car price prediction system.

It is designed to show how an enterprise setup is structured end to end:

- platform provisioning
- identity and credential management
- data ingestion and data versioning
- Azure ML training pipelines
- model registration and registry promotion
- test and prod deployment
- production monitoring and retraining
- Responsible AI review
- Azure DevOps based CI/CD with GitHub as source control
- Terraform-first infrastructure provisioning across Azure and Azure DevOps

This README is the main onboarding guide. A new engineer should be able to understand the system from here before going deeper into the supporting docs.

## What This Project Is

This repo is not just a training script bundle.

It is organized as a layered enterprise MLOps system:

1. `Platform layer`
   Provisions Azure resources like AML workspaces, registry, storage, Key Vault, ACR, monitoring foundations, and environment boundaries.
2. `Delivery layer`
   Uses Azure DevOps pipelines to validate code, provision infra, submit AML jobs, promote models, deploy endpoints, and manage approvals.
3. `ML execution layer`
   Contains the Azure ML components, training pipeline code, model registration flow, deployment logic, and scoring script.
4. `Operations layer`
   Defines monitoring, drift policy, retraining policy, Responsible AI expectations, and production operating guidance.
5. `Developer support layer`
   Keeps local smoke-test scripts for fast validation, but does not treat them as the production operating path.

## What This Project Is Not

This is not intended to mean:

- developers manually provision production resources from laptops
- local CSV files are the primary production data flow
- shell-exported secrets are the normal runtime credential model
- training happens locally in the normal enterprise path
- the latest model is deployed to prod without governance

Those shortcuts are useful only for developer smoke tests and debugging.

## High-Level Architecture

The intended enterprise path is:

1. Terraform provisions or updates platform resources across Azure and Azure DevOps.
2. Data lands in storage and is registered as AML data assets or MLTable.
3. Azure DevOps submits an Azure ML training pipeline.
4. Azure ML runs train/evaluate components on managed compute.
5. Approved candidate model is registered in workspace.
6. Approved model is promoted to a shared Azure ML registry.
7. Test deployment is created and smoke-tested.
8. Prod deployment is approval-gated and rolled out safely.
9. Monitoring runs continuously and may trigger retraining workflows.

## Tenant-Verified Inputs

The following Azure account details have already been verified interactively for this setup:

- Subscription name: `DemoPay`
- Subscription ID: `5c6c4978-12d9-43e0-8ba4-9fb538eb1e64`
- Tenant ID: `b6cb2304-83e3-47be-8adb-f6bb37058d52`
- Tenant display name: `Default Directory`

The chosen tenant architecture defaults are:

- region: `eastus`
- naming prefix: `usedcar`
- self-hosted Azure DevOps agents: `yes`
- private endpoints for storage, Key Vault, and ACR from day 1: `yes`
- Azure DevOps pipeline auth to Azure: `workload identity federation`
- Terraform bootstrap auth to Azure DevOps: `PAT`

The verified Azure CLI flow used was:

```bash
az login
az account set --subscription 5c6c4978-12d9-43e0-8ba4-9fb538eb1e64
az account show
```

The expected `az account show` result for this tenant should confirm:

- `name = DemoPay`
- `id = 5c6c4978-12d9-43e0-8ba4-9fb538eb1e64`
- `tenantId = b6cb2304-83e3-47be-8adb-f6bb37058d52`
- `state = Enabled`

Do not move to Terraform, AML provisioning, or Azure DevOps service-connection work until this check succeeds.

## Local Tooling Gate

Before infrastructure provisioning, verify the local Terraform version:

```bash
terraform version
```

This repo requires Terraform `>= 1.6.0`.

If Homebrew still shows `Terraform v1.5.7`, use this fix:

```bash
brew install tfenv
brew unlink terraform
brew link tfenv
tfenv install 1.9.8
tfenv use 1.9.8
terraform version
```

Only continue after `terraform version` shows `>= 1.6.0`.

## Directory Layout

```text
azure-mlops/
  azure-devops/   Azure DevOps pipeline definitions
  configs/        Environment-specific non-secret config
  data/           Synthetic data generator for smoke tests only
  deployment/     Endpoint and deployment YAML assets
  docs/           Operating model, identity, SRE, drift, RAI guidance
  infra/          Terraform-first and Bicep fallback infrastructure assets
  monitoring/     Monitor templates and production record schema
  pipelines/      AML submit/promote/deploy helper entrypoints
  src/            Train/evaluate/score implementation
```

## Layer By Layer

### 1. Platform Layer

Purpose:

- create Azure resources before any model training or serving happens
- separate `dev`, `test`, and `prod`
- provide storage, identity, secrets, monitoring, and registry foundations

Key files:

- [infra/terraform/README.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/README.md)
- [infra/terraform/main.tf](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/main.tf)
- [infra/bicep/main.bicep](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/bicep/main.bicep)
- [infra/bicep/modules/workspace.bicep](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/bicep/modules/workspace.bicep)
- [infra/bicep/README.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/bicep/README.md)
- [infra/provisioning-infra.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/provisioning-infra.md)

What happens here:

- resource groups are created per environment
- AML workspaces are created per environment
- supporting resources like storage, Key Vault, ACR, App Insights, and Log Analytics are created
- optionally a shared AML registry is created
- Azure DevOps service connection is provisioned
- Azure DevOps environments are provisioned
- Azure DevOps variable groups are provisioned

Production principle:

- infrastructure provisioning is a separate first-class lane
- do not rely on manual laptop execution as the normal path
- run this from Azure DevOps or your enterprise platform automation
- treat Azure resource provisioning and Azure DevOps provisioning as separate control planes
- prefer one IaC tool, Terraform, to manage both planes

### 2. Identity And Credentials Layer

Purpose:

- control who or what can provision, train, deploy, and read secrets
- keep secrets out of repo files and shell history

Key file:

- [docs/identity-and-credentials.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/identity-and-credentials.md)

Recommended model:

- Azure DevOps service connections for CI/CD identity
- workload identity federation preferred
- managed identities for AML compute and deployed endpoints
- Azure Key Vault for secret storage
- Azure DevOps variable groups backed by Key Vault

What is secret:

- external system credentials
- webhook secrets
- service principal secrets if still used

What is not secret:

- subscription ID
- resource group name
- workspace name
- registry name
- endpoint name

### 3. Delivery Layer

Purpose:

- turn infrastructure, training, promotion, deployment, and monitoring into repeatable pipelines

Key files:

- [azure-devops/azure-pipelines.yml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/azure-pipelines.yml)
- [azure-devops/azure-pipelines-monitoring.yml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/azure-pipelines-monitoring.yml)
- [azure-devops/README.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/README.md)
- [docs/azure-devops-operating-model.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/azure-devops-operating-model.md)

Pipeline lanes in this blueprint:

- `Validate`
  - linting/smoke validation
  - infra validation
- `Provision_Dev`
  - deploy platform resources
- `Train_Dev`
  - submit AML training pipeline
- `Promote_To_Test`
  - promote approved workspace model to registry
- `Deploy_Test`
  - deploy registry model to test endpoint
  - run smoke test
- `Deploy_Prod`
  - deploy to prod with approvals
- `Configure_Monitoring`
  - generate monitoring policy artifacts

Production principle:

- GitHub can remain the source repo
- Azure DevOps is the CI/CD engine
- approvals should live in Azure DevOps Environments
- Azure DevOps resources themselves should be provisioned separately from Azure resources

### 4. Configuration Layer

Purpose:

- hold non-secret environment-specific settings

Key files:

- [configs/dev.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/configs/dev.yaml)
- [configs/test.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/configs/test.yaml)
- [configs/prod.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/configs/prod.yaml)

These configs define things like:

- workspace names
- resource group names
- registry name
- endpoint names
- deployment instance sizes
- monitoring thresholds
- drift policy
- Responsible AI cohort settings

Production principle:

- keep secrets out of these files
- keep environment-specific operational policy inside these files where useful

### 5. Data Layer

Purpose:

- define how data is expected to enter the system

Key files:

- [data/generate_used_car_data.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/data/generate_used_car_data.py)
- [monitoring/production-schema.json](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/monitoring/production-schema.json)

How it works in production:

- upstream systems land data into ADLS / Blob / a governed storage path
- data is registered as AML data assets or MLTable
- AML training consumes those registered assets

Why the synthetic generator exists:

- developer smoke tests
- demonstrations
- local debugging

Production principle:

- synthetic CSV generation is not the real operating path
- production data should be versioned, governed, and registered

### 6. Azure ML Execution Layer

Purpose:

- run training, evaluation, registration, promotion, and deployment against Azure ML

Key files:

- [pipelines/training_pipeline.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/pipelines/training_pipeline.py)
- [pipelines/submit_training_pipeline.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/pipelines/submit_training_pipeline.py)
- [pipelines/register_model.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/pipelines/register_model.py)
- [pipelines/promote_model.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/pipelines/promote_model.py)
- [pipelines/deploy_model.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/pipelines/deploy_model.py)
- [pipelines/smoke_test_endpoint.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/pipelines/smoke_test_endpoint.py)
- [deployment/online-endpoint.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/deployment/online-endpoint.yaml)
- [deployment/blue-deployment.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/deployment/blue-deployment.yaml)

What happens here:

1. training pipeline is submitted to AML
2. AML runs train and evaluate components on compute
3. approved model is registered in workspace
4. approved model is promoted to shared registry
5. test deployment is created
6. smoke test is run
7. prod deployment is approval-gated

Production principle:

- prod should deploy from registry, not directly from ungoverned workspace artifacts

### 7. Application Serving Layer

Purpose:

- serve real-time predictions to applications

Key files:

- [src/score.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/src/score.py)
- [deployment/blue-deployment.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/deployment/blue-deployment.yaml)

How production prediction works:

1. a caller sends JSON to the online endpoint
2. AML routes the request to the active deployment
3. `score.py` loads the model and computes prediction
4. the response returns predicted used-car price
5. production records should capture request features, prediction, timestamp, and later actual price if it arrives

Production principle:

- deployed endpoint is part of a larger application path
- often fronted by an API or internal service

### 8. Monitoring And Retraining Layer

Purpose:

- detect quality issues, drift, and performance degradation after deployment

Key files:

- [monitoring/used-car-monitoring.yaml](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/monitoring/used-car-monitoring.yaml)
- [pipelines/generate_monitoring_config.py](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/pipelines/generate_monitoring_config.py)
- [docs/monitoring-retraining.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/monitoring-retraining.md)
- [docs/used-car-operating-policy.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/used-car-operating-policy.md)

What is monitored:

- service health
- data quality
- data drift
- prediction drift
- model performance when labels arrive later

What happens on threshold breach:

- alert is raised
- issue is inspected
- retraining candidate job may be triggered
- candidate must still pass evaluation and deployment gates

Production principle:

- drift does not automatically mean prod should be replaced
- retraining and redeployment should follow policy

### 9. Responsible AI Layer

Purpose:

- explain and audit model behavior

Key files:

- [docs/responsible-ai-used-car.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/responsible-ai-used-car.md)
- [docs/used-car-operating-policy.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/used-car-operating-policy.md)

How it is used:

- inspect errors by cohorts like brand, fuel type, transmission, year band
- inspect feature importance
- run counterfactual analysis
- use this during model review and after major retraining cycles

Production principle:

- Responsible AI is a governance and diagnostics layer
- not a replacement for deployment policy or monitoring

### 10. Scalability And SRE Layer

Purpose:

- ensure the system scales and can recover safely

Key file:

- [docs/scalability-and-sre.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/scalability-and-sre.md)

What matters here:

- AML compute autoscaling for training
- multiple endpoint instances in prod
- timeout and concurrency tuning
- blue/green or staged rollout
- rollback path
- latency and error SLOs

## Enterprise Setup Sequence

If you are setting this up in a real organization, follow this order:

1. Clone the repo and read this README.
2. Review [identity-and-credentials.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/identity-and-credentials.md).
3. Review [provisioning-infra.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/provisioning-infra.md).
4. Review [infra/terraform/README.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/README.md).
5. Adjust Terraform variables and naming standards for your Azure estate.
6. Provision Azure platform and Azure DevOps foundation resources.
7. Verify service connection, environments, and variable groups.
8. Register or prepare production data assets.
9. Run AML training via Azure DevOps.
10. Promote approved model to registry.
11. Deploy to test, then prod.
12. Configure and operate monitoring/retraining.

## Day 1 Execution Order

This is the exact recommended order for first real execution in your tenant.

### Phase 1: Azure Account Verification

Run:

```bash
az login
az account set --subscription 5c6c4978-12d9-43e0-8ba4-9fb538eb1e64
az account show
```

Success criteria:

- subscription is `DemoPay`
- tenant is `Default Directory`
- tenant ID is `b6cb2304-83e3-47be-8adb-f6bb37058d52`
- subscription state is `Enabled`

### Phase 2: Terraform Foundation Inputs

Before running Terraform, gather and fill:

- Azure DevOps org URL
- Azure DevOps project name
- bootstrap Azure DevOps PAT
- service principal or federated identity details for the Azure service connection
- final naming overrides if your organization requires them

Fill those in:

- [infra/terraform/terraform.tfvars.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/terraform.tfvars.example)

Create:

- `azure-mlops/infra/terraform/terraform.tfvars`

#### How To Get These Values

##### 1. Azure DevOps org URL

What it is:

- the base URL of your Azure DevOps organization

How to get it:

1. Open Azure DevOps in the browser.
2. Look at the URL in the address bar.
3. It usually looks like one of these:
   - `https://dev.azure.com/<org-name>`
   - older format: `https://<org-name>.visualstudio.com`

What to put in Terraform:

```hcl
azure_devops_org_service_url = "https://dev.azure.com/<your-org>"
```

Where to update:

- [terraform.tfvars.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/terraform.tfvars.example)
- your real `azure-mlops/infra/terraform/terraform.tfvars`

##### 2. Azure DevOps project name

What it is:

- the Azure DevOps project where pipelines, environments, and variable groups will live

How to get it:

1. Open Azure DevOps.
2. In the top-left project selector, note the selected project name.
3. Or look at the URL path after the organization name:
   - `https://dev.azure.com/<org-name>/<project-name>`

What to put in Terraform:

```hcl
azure_devops_project_name = "<your-project>"
```

Where to update:

- [terraform.tfvars.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/terraform.tfvars.example)
- your real `azure-mlops/infra/terraform/terraform.tfvars`

##### 3. Azure DevOps PAT

What it is:

- a Personal Access Token used only for Terraform bootstrap against Azure DevOps if you are provisioning Azure DevOps objects through the Terraform provider

How to get it:

1. Open Azure DevOps.
2. Click your profile icon.
3. Open `Personal access tokens`.
4. Create a new token.
5. Give it a short-lived name such as `terraform-bootstrap-amlops`.
6. Grant the minimum scopes needed for:
   - project and team read
   - service connections if required
   - variable groups / library
   - environments / pipeline administration as needed

Recommended practical scope set for this repo:

- `Project and Team (Read)`
- `Build (Read)`
- `Release (Read)` if classic release features are still in use
- `Service Connections (Read, query, and manage)`
- `Variable Groups / Library (Read, create, and manage)`
- `Environment (Read, manage)`

What to put in Terraform:

Production note:

- this PAT is a bootstrap mechanism, not the long-term runtime secret model
- do not commit it
- do not store it in `terraform.tfvars`
- store it in Azure Key Vault and export it at runtime instead

Where to update:

- do not place it in the tracked tfvars file
- pass it at runtime as `TF_VAR_azure_devops_pat`

Recommended runtime pattern:

```bash
export TF_VAR_azure_devops_pat="$(az keyvault secret show \
  --vault-name <your-keyvault-name> \
  --name azure-devops-pat \
  --query value -o tsv)"
```

If Terraform reports:

```text
You are not authorized to access Azure DevOps Organization
```

then usually one of these is wrong:

- the org URL
- the PAT org
- the PAT scopes
- the PAT expiration or revocation state
- the PAT owner’s access to the target Azure DevOps project

How to store the PAT in Azure Key Vault:

```bash
az keyvault secret set \
  --vault-name <your-keyvault-name> \
  --name azure-devops-pat \
  --value "<your-pat>"
```

##### 4. Auth choice for Azure service connection

What it is:

- the authentication method Azure DevOps will use to talk to Azure

Recommended choices:

1. workload identity federation
2. service principal with certificate
3. service principal with secret

Important:

- the Azure DevOps PAT is only for Terraform-to-Azure-DevOps bootstrap
- workload identity federation is for Azure DevOps pipeline access to Azure

What this repo currently expects in the Terraform starter:

- a service principal client ID
- a service principal secret

How to get service principal values if using secret-based auth:

1. Open Azure Portal.
2. Go to `Microsoft Entra ID`.
3. Go to `App registrations`.
4. Create or select the app registration for Azure DevOps CI/CD.
5. Copy:
   - `Application (client) ID`
   - `Directory (tenant) ID`
6. Go to `Certificates & secrets`.
7. Create a client secret.
8. Copy the secret value immediately.

What to put in Terraform:

```hcl
tenant_id            = "<tenant-id>"
service_principal_id = "<client-id>"
service_principal_key = "<client-secret>"
```

Where to update:

- [terraform.tfvars.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/terraform.tfvars.example)
- your real `azure-mlops/infra/terraform/terraform.tfvars`

##### 5. Subscription name and ID

You already verified:

```hcl
subscription_id   = "5c6c4978-12d9-43e0-8ba4-9fb538eb1e64"
subscription_name = "DemoPay"
tenant_id         = "b6cb2304-83e3-47be-8adb-f6bb37058d52"
```

Where to update:

- [terraform.tfvars.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/terraform.tfvars.example)
- your real `azure-mlops/infra/terraform/terraform.tfvars`

##### 6. Naming prefix and region

What they are:

- the resource naming prefix and Azure region for deployed resources

How to choose them:

- use your enterprise naming convention if one exists
- otherwise the starter defaults are:
  - `prefix = "usedcar"`
  - `location = "eastus"`

Where to update:

- [terraform.tfvars.example](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform/terraform.tfvars.example)
- your real `azure-mlops/infra/terraform/terraform.tfvars`

##### 7. Networking choice

You must choose one of these paths:

1. `public access for now`
2. `private networking from day 1`

What private networking means in this project:

- Azure ML dependencies are accessed through private networking controls
- storage, Key Vault, and ACR usually get private endpoints
- VNet, subnets, and private DNS zones become part of the platform design
- Azure DevOps execution may require self-hosted agents or another network-aware execution path

Where to read more:

- [provisioning-infra.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/provisioning-infra.md)
- [identity-and-credentials.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/identity-and-credentials.md)

### Phase 3: Terraform Validation

Run:

```bash
cd /Users/amit/Desktop/Code\ 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/terraform
terraform init
terraform validate
terraform plan
```

Success criteria:

- provider initialization succeeds
- Azure subscription auth succeeds
- Azure DevOps project lookup succeeds
- no schema or naming errors remain

If this fails, fix the tenant-specific values or Terraform definitions before going further.

### Phase 4: Terraform Apply

Run:

```bash
terraform apply
```

Success criteria:

- Azure resources are created
- Azure DevOps service connection is created
- Azure DevOps environments are created
- Azure DevOps variable groups are created

### Phase 5: Foundation Verification

Verify in Azure Portal:

- `rg-aml-dev`, `rg-aml-test`, `rg-aml-prod`
- `aml-ws-dev`, `aml-ws-test`, `aml-ws-prod`
- storage, Key Vault, ACR, Log Analytics, App Insights
- AML registry if enabled

Verify in Azure DevOps:

- service connection `az-mlops-sc`
- environments:
  - `aml-test-approval`
  - `aml-test`
  - `aml-prod`
- variable groups:
  - `aml-dev-shared`
  - `aml-test-shared`
  - `aml-prod-shared`

### Phase 6: Local Smoke Validation

Only after foundation exists, run:

```bash
cd /Users/amit/Desktop/Code\ 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=. python data/generate_used_car_data.py --rows 500 --output /tmp/used_cars.csv
PYTHONPATH=. python -m src.train --train_data /tmp/used_cars.csv --model_output /tmp/used-car-model --metrics_output /tmp/used-car-metrics.json
PYTHONPATH=. python -m src.evaluate --metrics_input /tmp/used-car-metrics.json --evaluation_output /tmp/used-car-eval.json
```

This is a developer smoke test only, not the enterprise operating path.

### Phase 7: First AML Cloud Run

Generate starter data if needed:

```bash
cd /Users/amit/Desktop/Code\ 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops
source .venv/bin/activate
PYTHONPATH=. python data/generate_used_car_data.py --rows 10000 --output data/used_cars.csv
```

Submit training:

```bash
export AZURE_SUBSCRIPTION_ID=5c6c4978-12d9-43e0-8ba4-9fb538eb1e64
PYTHONPATH=. python pipelines/submit_training_pipeline.py --env dev --data data/used_cars.csv
```

Success criteria:

- AML job is created
- train/evaluate steps complete
- candidate model is available

### Phase 8: Register, Promote, Deploy

Promote the approved workspace model:

```bash
PYTHONPATH=. python pipelines/promote_model.py \
  --env dev \
  --model-name used-car-price-model \
  --workspace-model-version <workspace_model_version>
```

Deploy to test:

```bash
PYTHONPATH=. python pipelines/deploy_model.py \
  --env test \
  --model-name used-car-price-model \
  --model-version <registry_model_version> \
  --source registry
```

Smoke test:

```bash
PYTHONPATH=. python pipelines/smoke_test_endpoint.py --env test
```

### Phase 9: Azure DevOps Pipeline Verification

After manual bootstrap succeeds, run the Azure DevOps pipeline path and verify:

- validation stage works
- infra stage works
- train stage works
- promote stage works
- deploy stage works

At that point, the setup is much closer to a true cloud-verified tenant implementation.

## How To Use This Repo Today

### Enterprise-first path

Start from:

- [azure-devops/README.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/azure-devops/README.md)
- [docs/production-operations.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/production-operations.md)
- [docs/azure-devops-operating-model.md](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/azure-devops-operating-model.md)

### Developer-only smoke path

These commands are for local validation only:

```bash
cd /Users/amit/Desktop/Code\ 1_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=. python data/generate_used_car_data.py --rows 500 --output /tmp/used_cars.csv
PYTHONPATH=. python -m src.train --train_data /tmp/used_cars.csv --model_output /tmp/used-car-model --metrics_output /tmp/used-car-metrics.json
PYTHONPATH=. python -m src.evaluate --metrics_input /tmp/used-car-metrics.json --evaluation_output /tmp/used-car-eval.json
```

Use them when:

- onboarding a developer
- verifying code changes quickly
- debugging the model logic without waiting for cloud resources

Do not treat them as the normal production operating flow.

## Key Supporting Docs

- [Enterprise Blueprint](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/enterprise-blueprint.md)
- [Provisioning Infrastructure](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/infra/provisioning-infra.md)
- [Production Operations](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/production-operations.md)
- [Azure DevOps Operating Model](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/azure-devops-operating-model.md)
- [Identity And Credentials Strategy](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/identity-and-credentials.md)
- [Scalability And SRE Guidance](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/scalability-and-sre.md)
- [Monitoring and Retraining](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/monitoring-retraining.md)
- [Used Car Operating Policy](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/used-car-operating-policy.md)
- [Responsible AI for Used Car Price Prediction](/Users/amit/Desktop/Code%201_pers/PersonalProjects/AgenticAI/Azure-agentic-setup/official-repo/azure-mlops/docs/responsible-ai-used-car.md)

## Design Principles

- infrastructure provisioning is a first-class separate lane
- secrets should be externalized to Key Vault and identities
- training should run in Azure ML, not as the normal laptop path
- registry promotion should separate candidate creation from approved deployment
- prod deployments should be approval-gated
- monitoring and retraining should be continuous post-deployment concerns

## Notes

- This project is intentionally Azure ML SDK v2 centered.
- The model implementation uses scikit-learn `RandomForestRegressor` for portability.
- GitHub is the source-control system; Azure DevOps is the intended enterprise CI/CD engine.
- The Terraform, Bicep fallback, and pipeline assets are opinionated starters and should be aligned with your landing zone, networking, and governance standards.
