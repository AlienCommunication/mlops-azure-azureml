# Setup Walkthrough — What We Built, In Order, And Why

This document is the chronological record of how this platform was actually
stood up in the `DemoPay` tenant, including the failures along the way and
what each one taught us. Read it top to bottom to understand not just what
exists, but why it exists.

Companion documents:

- [concepts.md](concepts.md) — plain-language explanations of every building
  block used here (self-hosted agents, private endpoints, Terraform state...)
- [../infra/platform-inventory.md](../infra/platform-inventory.md) — the
  complete, frozen inventory of what Terraform provisions

---

## Phase 0 — Day-0 bootstrap (manual, one time)

**What:** Azure DevOps project `mlops1`, a PAT, the Azure service connection
`az-mlops-sc`, the variable group `aml-infra-tfvars`, the secret variable
`AZURE_DEVOPS_PAT`.

**Why manual:** a pipeline cannot create the project it runs in or the
credentials it authenticates with. Every production setup, at any company,
has this irreducible manual "root of trust" step. Production-grade does not
mean zero manual steps — it means the manual steps are few, documented, and
never repeated.

## Phase 1 — Terraform remote state

**What:** a dedicated storage account (`stusedcartfstate01`) holding one
state blob, created idempotently by `bootstrap_backend.sh`, which the infra
pipeline runs automatically before every `terraform init`.

**Why:** Terraform records everything it owns in a state file. If each
pipeline run starts with empty state, Terraform tries to re-create resources
that already exist and Azure answers `AlreadyExists` — which is exactly the
failure this project hit early on (see Lesson 1).

**Lesson 1 — state drift.** An early apply ran before remote state was
stable, so real Azure resources existed that no state file knew about. Every
later apply failed with `already exists` errors. The fix was to *import*
those resources into state — never to delete and recreate them, and never to
add "skip if exists" hacks. The repo now handles this declaratively: gated
`import` blocks in `imports.tf` (`terraform apply -var
'bootstrap_adopt=["all"]'`) for Azure resources, and
`import_azdo_bootstrap.sh` for Azure DevOps objects whose numeric IDs
require a REST lookup.

## Phase 2 — The platform in one Terraform stack

**What:** everything in [platform-inventory.md](../infra/platform-inventory.md):
networking (VNet, subnets, NAT, NSGs, private DNS), per-environment core
(storage, Key Vault, ACR, monitoring), Azure ML (workspaces, registry,
compute clusters), and the Azure DevOps objects (environments, variable
groups, agent pool).

**Why one stack:** Azure resources and Azure DevOps resources are two
control planes, but one Terraform stack can own both, which avoids a split
infrastructure story. The infra pipeline plans, waits for approval on the
`aml-platform-infra` environment, then applies.

**Lesson 2 — the ML registry payload.** The registries API rejects an empty
`properties` body: it requires `regionDetails` (which region(s) replicate
the registry, plus its system-created storage account and Premium ACR), and
registries take no `sku` at all. The apply error was an opaque 400; the fix
came from reading the REST contract in the official `azure-sdk-for-python`
models.

## Phase 3 — The networking decision

Everything (storage, Key Vault, ACR, workspaces) was created with
`publicNetworkAccess = Disabled`. That is the enterprise security posture —
but it creates a problem: **Microsoft-hosted pipeline agents live on the
public internet**, and job submission uploads code to workspace storage,
which the storage firewall now rejects.

Two ways out:

1. **Open public access** (fast, free, weaker posture) — prove the ML lane,
   then tighten later.
2. **Self-hosted agents inside the VNet** (the chosen path) — CI/CD jobs run
   on machines that can reach the private endpoints, keeping the data plane
   fully private.

## Phase 4 — The self-hosted agent lane

**What is a self-hosted agent?** The agent is the worker machine that
executes pipeline job steps. Microsoft-hosted agents are throwaway VMs in
Microsoft's cloud — convenient, free-tier, but outside your network.
A *self-hosted* agent is a machine you own. Ours live inside the VNet, so
pipeline steps can reach the private workspaces.

Key properties of an agent worth knowing:

- Agents make **outbound-only** connections: they poll `dev.azure.com` over
  HTTPS asking for work. Azure DevOps never connects *in* — so an agent
  with no public IP is unreachable from the internet.
- An agent runs whatever the pipeline tells it to. That is why the pool
  requires explicit **pipeline permission** before any YAML pipeline may
  use it (Lesson 4).

**How ours is built (all Terraform):**

| Piece | What it does |
|-------|--------------|
| VMSS `usedcar-agents-vmss` | Ubuntu 22.04 scale set, no public IPs, in `snet-selfhosted-agents`. Cloud-init installs the Azure CLI; Ubuntu 22.04 ships Python 3.10 natively. |
| Elastic pool `aml-selfhosted-agents` | Azure DevOps manages the VMSS: installs the agent software on new VMs, scales 0→2 with queued jobs, deletes idle VMs after ~15 min. Scale-to-zero means VMs cost nothing while idle. |
| NAT gateway | Subnets created after Sep 2025 have **no default outbound internet**. The NAT gateway provides the outbound path agents need to reach Azure DevOps, PyPI, etc. Outbound-only by design. |
| NSGs | Baseline segmentation on the agents and training subnets (deny inbound from internet, allow outbound). |

**Workspace private endpoints:** being inside the VNet is not enough — a
private workspace is only reachable through its own private endpoint plus
the AML DNS zones (`privatelink.api.azureml.ms`,
`privatelink.notebooks.azure.net`). Without these, even an in-VNet agent
gets refused.

**Lesson 3 — first-job latency is not a hang.** With scale-to-zero, the
first job waits 5–10 minutes while a VM boots and registers. Watch the pool
page → Agents tab to see it come online.

**Lesson 4 — pool authorization.** A new pool cannot be used by any YAML
pipeline until at least one pipeline is permitted on it: pool page →
Security → *Pipeline permissions*. This is a deliberate security gate,
because agents execute arbitrary pipeline code inside your network. Note
that agent pools have TWO security panels — *user* permissions (people) and
*pipeline* permissions (YAML pipelines); the error "Pipeline does not have
permissions to use the referenced pool" is about the second.

## Phase 5 — ML compute and data

**Compute clusters** (`cpu-cluster-{env}`): AML training does not run on
CI agents — the agent only *submits* jobs. Training runs on AML compute
clusters, which are VNet-injected into `snet-aml-training` with no public
node IPs so they can read the private storage. They scale 0→2 and cost
nothing idle.

**Image builds:** with a private ACR, AML cannot use ACR Tasks to build
environment images, so each workspace sets `imageBuildCompute` — builds run
on the compute cluster itself. The first training run therefore includes a
~10–20 minute one-time image build.

**Data asset:** training references `azureml:used-car-training-reference:1`.
The Train stage generates the demo CSV and registers it as a versioned AML
data asset (idempotent — skips if the version already exists). In a real
organization, upstream systems land data and you register that instead.

## Phase 6 — The automated ML delivery chain

The ML pipeline (`azure-pipelines.yml`) stages and the handoffs between
them:

1. **Validate** (hosted agent) — quick smoke train on synthetic data.
2. **Train_Dev** (self-hosted) — register data → submit the AML pipeline
   (train component → evaluate component) → *stream the job to completion*
   → enforce the evaluation gate (RMSE/R² thresholds) → register the model
   → emit `WORKSPACE_MODEL_VERSION` as a stage output variable.
3. **Promote_To_Test** (self-hosted, approval-gated) — consume that
   version, copy the model to the shared registry, emit
   `REGISTRY_MODEL_VERSION`.
4. **Deploy_Test** (self-hosted) — deploy the registry model to the test
   endpoint, run a smoke request.
5. **Deploy_Prod** (self-hosted, approval-gated) — same to prod.
6. **Configure_Monitoring** (hosted) — generate monitoring config artifact.

**Why the version handoff matters:** previously `WORKSPACE_MODEL_VERSION`
was a manually-set pipeline variable — a human had to look up a number and
type it in. Now versions flow automatically between stages, and humans
contribute exactly what humans should: the approval decisions.

**Why train "waits" now:** the old pipeline submitted the AML job and went
green seconds later, regardless of whether training later failed. Now the
stage streams the job and fails when training fails — a green run means a
trained, gated, registered model.

**Lesson 5 — node allocation can stall silently.** One training run sat
"stuck" for ~50 minutes: the cluster showed `allocationState: Resizing`,
`target: 1`, `current: 0`, no errors — Azure Batch had allocated a VM (its
NIC was visible in the subnet) whose bootstrap crawled, then recovered on
its own. Nothing in the repo was wrong. Diagnosis command (control-plane,
works from anywhere):

```bash
az ml compute show -n cpu-cluster-dev -w aml-ws-dev -g rg-aml-dev
az resource show --ids <cluster-resource-id> \
  --query "properties.properties.{allocState:allocationState, current:currentNodeCount, target:targetNodeCount, errors:errors}"
```

Rule of thumb: silent under ~20 minutes — wait; 45+ minutes — investigate;
`errors` populated or chronic stalls — switch to a newer VM family
(`TF_VAR_compute_vm_size` in the `aml-infra-tfvars` variable group) or keep
a warm node (`min_instances = 1`). The submit script now has a watchdog
(`--timeout-minutes`, default 60) that cancels the job and fails the stage
loudly instead of hanging the pipeline.

## Deliberate trade-offs at this stage

- Studio (browser) access to the private workspaces is blocked from
  outside the VNet — needs VPN/Bastion or a temporary public-access flip.
- No egress firewall on agent outbound traffic (cost-disproportionate here).
- Key Vault purge protection off (demo subscription; enable in a real tenant).
- Model monitoring definitions exist but are not yet applied as live
  AML monitors.
