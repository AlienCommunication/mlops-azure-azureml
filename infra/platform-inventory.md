# Platform Inventory — The Infrastructure Contract

This document is the complete, final list of what the Terraform stack
(`infra/bicep/terraform`) provisions. After this version is applied, the
platform is **frozen for the ML delivery milestone**: everything the ML
pipelines need exists, and ML work (Python, pipeline YAML, configs) must
never require a Terraform change.

Any future Terraform change is a deliberate *platform* change — reviewed in
its own PR, visible in the plan output, and applied through the infra
pipeline. Infra changes are normal in production operations; *surprise*
infra changes are not.

## Layer 0 — Bootstrap (manual, one-time, documented)

| Object | Where | Why manual |
|--------|-------|-----------|
| Azure DevOps project, PAT | Azure DevOps | Pipelines cannot pre-exist their own project/credentials |
| Service connection `az-mlops-sc` (subscription Contributor) | Azure DevOps | Root of trust between AzDO and Azure |
| Variable group `aml-infra-tfvars` (`TF_VAR_*`, `TF_BACKEND_*`) | Azure DevOps | Pipeline configuration source |
| Secret variable `AZURE_DEVOPS_PAT` | Infra pipeline | Terraform's auth to the AzDO provider |

Terraform state backend (`rg-usedcar-tfstate` / `stusedcartfstate01` /
`tfstate`) is created automatically by the infra pipeline via
`bootstrap_backend.sh` (idempotent).

## Layer 1 — Networking (rg-aml-network)

| Resource | Name | Purpose |
|----------|------|---------|
| VNet | `usedcar-vnet` (10.20.0.0/16) | Private network for everything below |
| Subnet | `snet-private-endpoints` (10.20.1.0/24) | All private endpoints |
| Subnet | `snet-selfhosted-agents` (10.20.2.0/24) | CI/CD agent VMSS |
| Subnet | `snet-aml-training` (10.20.3.0/24) | VNet-injected AML compute |
| NAT gateway + public IP | `usedcar-agents-nat` | Outbound internet for agents + training subnets (no default outbound for new subnets) |
| NSG | `usedcar-agents-nsg`, `usedcar-training-nsg` | Baseline segmentation on compute subnets |
| Private DNS zones ×7 + VNet links | blob, file, vault, acr, aml api, aml notebooks | Private name resolution for all private endpoints |

## Layer 2 — Per-environment core (rg-aml-{dev,test,prod})

| Resource | Name pattern | Notes |
|----------|--------------|-------|
| Storage account | `usedcar{env}stg01` | TLS1.2, public access disabled |
| Key Vault | `usedcar-{env}-kv` | RBAC mode, public access disabled |
| Container registry | `usedcar{env}acr01` | Premium (required for private), public access disabled |
| Log Analytics | `log-aml-{env}` | 30-day retention |
| Application Insights | `appi-aml-{env}` | Workspace-based |
| Private endpoints ×5 | `usedcar-{env}-{stg,file,kv,acr,ws}-pe` | Blob, file, Key Vault, ACR, AML workspace |

## Layer 3 — Azure ML (per environment + shared)

| Resource | Name | Notes |
|----------|------|-------|
| AML workspace | `aml-ws-{env}` | publicNetworkAccess=Disabled; `imageBuildCompute` set (private ACR cannot use ACR Tasks) |
| Compute cluster | `cpu-cluster-{env}` | VNet-injected in `snet-aml-training`, no public node IPs, scale 0–2, 30-min idle scale-down |
| ML registry | `aml-enterprise-registry` (rg-aml-shared) | Public endpoint (no PE); system-created storage + Premium ACR in managed RG |

## Layer 4 — Azure DevOps (Terraform-managed)

| Resource | Name | Purpose |
|----------|------|---------|
| Environments | `aml-test-approval`, `aml-test`, `aml-prod` | Approval gates |
| Variable groups | `aml-{env}-shared` | Non-secret ML pipeline config |
| Elastic agent pool | `aml-selfhosted-agents` | VMSS-backed, scale-to-zero, in-VNet |
| Agent VMSS | `usedcar-agents-vmss` (rg-aml-network) | Ubuntu 22.04, B2ms, cloud-init installs Azure CLI |

## Deliberate exclusions (decided, not forgotten)

- **Storage queue/table private endpoints** — only needed by AML v1
  ParallelRunStep-style features; this project is SDK v2 command jobs.
- **Registry private endpoint** — registry stays public so promote/deploy
  work from any agent; acceptable because it holds models, not data.
- **Key Vault purge protection** — one-way flag; intentionally off in this
  demo subscription to keep teardown possible. Enable for a real tenant.
- **Egress firewall (Azure Firewall/FQDN rules)** — disproportionate cost
  here (~$250+/mo); the documented enterprise hardening step.
- **VPN/Bastion for Studio access** — workspaces are private; browser
  access needs a network path. Decide when needed.

## Steady-state costs to be aware of

NAT gateway (~$32/mo) and 15 private endpoints (~$110/mo) run continuously.
Registry's system-created Premium ACR (~$50/mo). Agent VMs and compute
cluster nodes bill only while running (both scale to zero).
