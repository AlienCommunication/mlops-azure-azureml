# Concepts — The Building Blocks Explained

Plain-language explanations of every moving part in this platform: what it
is, what problem it solves, and how this repo uses it. Companion to
[setup-walkthrough.md](setup-walkthrough.md) (the chronological story).

---

## CI/CD layer

### Pipeline agent

The worker machine that executes your pipeline's steps (checkout, scripts,
tasks). When a job runs, Azure DevOps hands it to an agent from a **pool**.

### Microsoft-hosted agent

A fresh, throwaway VM in Microsoft's cloud (`vmImage: ubuntu-latest`).
Zero maintenance, free tier available — but it lives on the public
internet, so it cannot reach resources that are private-network-only.
This repo uses hosted agents only for stages that never touch private
resources (Validate, monitoring-config generation).

### Self-hosted agent

An agent on a machine *you* own. Ours run inside the VNet, which is the
entire point: pipeline steps can reach the private AML workspaces and
storage. Two facts do most of the security work: agents make
**outbound-only** connections (they poll `dev.azure.com`; nothing connects
in), and ours have **no public IPs** — there is no internet-reachable
surface.

### VMSS (Virtual Machine Scale Set) + elastic pool

A VMSS is a group of identical VMs Azure can scale up/down as one unit. An
Azure DevOps **elastic pool** wraps a VMSS: AzDO installs the agent
software on new instances automatically, grows the set when jobs queue,
and deletes idle VMs after a TTL. Ours scales 0→2 — **scale-to-zero**
means you pay for agent VMs only while jobs run. Trade-off: the first job
after idle waits ~5–10 minutes for a VM to boot.

### Pipeline permissions vs user permissions

Agent pools have two separate security lists. *User permissions* control
which people can administer the pool. *Pipeline permissions* control which
YAML pipelines may run jobs on it — a new pool starts with **none**, and
the error "Pipeline does not have permissions to use the referenced pool"
means exactly that. It is a deliberate gate: agents execute arbitrary
pipeline code inside your network, so each pipeline must be explicitly
trusted (pool page → Security → Pipeline permissions).

### Environments and approval gates

Azure DevOps **Environments** (`aml-test-approval`, `aml-prod`, ...) are
named deployment targets you can attach checks to — most importantly,
human approvals. Our promote and prod-deploy stages pause until a person
approves. This is where governance lives: automation moves the model,
humans decide whether it should move.

### Service connection & workload identity federation (WIF)

The **service connection** (`az-mlops-sc`) is Azure DevOps' identity for
touching Azure — the root of trust, created manually on day 0. It can
authenticate with a client secret (a password that can leak/expire) or via
**workload identity federation**: Azure trusts short-lived tokens issued
by Azure DevOps directly, no stored secret at all. WIF is the modern
recommendation; the infra pipeline supports both automatically.

### PAT (Personal Access Token)

A user-scoped Azure DevOps token. Terraform's AzDO provider uses one
(`AZURE_DEVOPS_PAT`) to create environments, variable groups, and the
agent pool. Bootstrap-only, stored as a secret variable, rotatable. Needs
the "Agent Pools (Read & manage)" scope for the elastic pool.

---

## Networking layer

### VNet and subnets

The private network (`usedcar-vnet`, 10.20.0.0/16) everything sensitive
lives in. Subnets segment it by role: `snet-private-endpoints` (all
private endpoints), `snet-selfhosted-agents` (CI agents),
`snet-aml-training` (training compute).

### Private endpoint (PE)

A network card inside your VNet that *is* a specific Azure resource's
private address. With `publicNetworkAccess: Disabled` on the resource, the
PE becomes the only way in: traffic stays on the Azure backbone, never the
public internet. Each environment has five: blob storage, file storage,
Key Vault, ACR, and the AML workspace itself.

### Private DNS zone

PEs are useless unless names resolve to them. A private DNS zone (e.g.
`privatelink.blob.core.windows.net`) linked to the VNet makes
`usedcardevstg01.blob.core.windows.net` resolve to the PE's private IP for
anything inside the VNet — while the rest of the world still sees (and is
rejected by) the public endpoint. Seven zones cover blob, file, vault,
ACR, AML API, and AML notebooks.

### NAT gateway

Provides *outbound* internet for subnets whose VMs have no public IPs
(agents need to reach Azure DevOps and PyPI; compute nodes need the AML
control plane). Azure removed default outbound access for new subnets
(Sept 2025), so this is now mandatory, not optional. Outbound-only by
design — it cannot accept inbound connections.

### NSG (Network Security Group)

A firewall attached to a subnet. Ours enforce the baseline: traffic within
the VNet allowed, inbound from the internet denied, outbound allowed.
Attaching one makes the posture explicit and auditable rather than
implicit default behavior.

---

## Infrastructure-as-code layer

### Terraform state & remote backend

Terraform records every resource it manages in a **state file**. Ours
lives in a dedicated Azure storage blob (the **remote backend**) so CI
runs and laptops share one source of truth. Golden rule: *Terraform is
state-driven, not existence-driven* — a resource that exists in Azure but
not in state will be re-created, and Azure will answer `AlreadyExists`.

### Import / adoption

The fix for the above: telling Terraform "this existing resource is yours."
This repo does it declaratively with gated `import` blocks
(`terraform apply -var 'bootstrap_adopt=["all"]'` — see
`infra/bicep/terraform/imports.tf`), which run through plan review like
any other change. Azure DevOps objects need `import_azdo_bootstrap.sh`
because their numeric IDs require a REST lookup.

### The bootstrap paradox

Terraform cannot create the storage account its own state lives in, and a
pipeline cannot create the project/credentials it runs with. Hence exactly
two scripts: `bootstrap_backend.sh` (state backend, run automatically by
the pipeline, idempotent) and the day-0 manual objects (project, PAT,
service connection, variable group).

---

## Azure ML layer

### Workspace

The top-level AML container per environment (`aml-ws-dev/test/prod`):
jobs, models, data assets, compute, endpoints all live in one. Ours are
`publicNetworkAccess: Disabled` — reachable only through their private
endpoints.

### Compute cluster

Where training actually runs (`cpu-cluster-{env}`). The CI agent only
*submits* jobs; AML executes them on the cluster. Ours are VNet-injected
(nodes sit in `snet-aml-training`, no public IPs) so they can read private
storage, and scale 0→2 so idle cost is zero.

### Environment (AML sense) & image builds

A versioned Docker+conda definition of training dependencies
(`used-car-training-env`). AML builds it into a container image once and
reuses it. Because our ACR is private, ACR Tasks can't build images — the
workspace's `imageBuildCompute` setting routes builds onto the compute
cluster instead (this is why the first training run takes ~15 min longer).

### Data asset

A named, versioned pointer to data (`used-car-training-reference:1`).
Jobs reference the name+version instead of raw paths, which gives you
reproducibility and lineage ("model v7 was trained on data v1").

### Components & the training pipeline

Reusable pipeline steps with typed inputs/outputs. This project has two —
`train` and `evaluate` — chained by `pipelines/training_pipeline.py`.
The evaluate component is the **quality gate**: it writes
`approved: true/false` from RMSE/R² thresholds, and CI refuses to register
a rejected model.

### Model registry (shared)

A tenant-wide store (`aml-enterprise-registry`) above the workspaces.
Models are *promoted* from a dev workspace into it, and test/prod deploy
*from* it — so what runs in prod is a governed, immutable artifact, not
"whatever is in the dev workspace."

### Managed online endpoint

AML-hosted real-time serving. An **endpoint** is the stable URL + auth;
a **deployment** (e.g. `blue`) is a model+code+VM configuration behind it.
Traffic percentages let you do blue/green rollouts. `src/score.py` is the
code that answers each request.

---

## The two-pipeline mental model

The **AML pipeline** (train → evaluate) is the ML workload; it runs in
Azure ML on cluster nodes. The **Azure DevOps pipeline** is the delivery
conveyor around it: validate → train (submit + gate + register) → promote
→ deploy test → deploy prod → monitoring, with human approvals between.
Keeping them distinct is what makes the system explainable: data
scientists own the first, platform/MLOps owns the second.
