data "azurerm_client_config" "current" {}

data "azuredevops_project" "project" {
  name = var.azure_devops_project_name
}

locals {
  env_map = {
    for env in var.environments : env => {
      resource_group_name = "rg-aml-${env}"
      workspace_name      = "aml-ws-${env}"
      storage_name        = substr(replace(lower("${var.prefix}${env}stg01"), "-", ""), 0, 24)
      key_vault_name      = substr(replace(lower("${var.prefix}-${env}-kv"), "_", "-"), 0, 24)
      app_insights_name   = "appi-aml-${env}"
      log_analytics_name  = "log-aml-${env}"
      acr_name            = substr(replace(lower("${var.prefix}${env}acr01"), "-", ""), 0, 50)
    }
  }

  key_vault_service_endpoint_id = var.existing_service_endpoint_id != null ? var.existing_service_endpoint_id : try(azuredevops_serviceendpoint_azurerm.arm[0].id, null)

  create_key_vault_linked_variable_groups = var.enable_key_vault_linked_variable_groups && local.key_vault_service_endpoint_id != null
}

resource "azurerm_resource_group" "network" {
  count = var.enable_private_networking ? 1 : 0

  name     = "rg-aml-network"
  location = var.location
  tags     = merge(var.tags, { environment = "shared" })
}

resource "azurerm_virtual_network" "shared" {
  count = var.enable_private_networking ? 1 : 0

  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.network[0].location
  resource_group_name = azurerm_resource_group.network[0].name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "private_endpoints" {
  count = var.enable_private_networking ? 1 : 0

  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.network[0].name
  virtual_network_name = azurerm_virtual_network.shared[0].name
  address_prefixes     = [var.private_endpoints_subnet_prefix]
}

resource "azurerm_subnet" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  name                 = "snet-selfhosted-agents"
  resource_group_name  = azurerm_resource_group.network[0].name
  virtual_network_name = azurerm_virtual_network.shared[0].name
  address_prefixes     = [var.agents_subnet_prefix]
}

resource "azurerm_resource_group" "env" {
  for_each = local.env_map

  name     = each.value.resource_group_name
  location = var.location
  tags     = merge(var.tags, { environment = each.key })
}

resource "azurerm_resource_group" "shared" {
  count = var.create_registry ? 1 : 0

  name     = "rg-aml-shared"
  location = var.location
  tags     = merge(var.tags, { environment = "shared" })
}

resource "azurerm_storage_account" "env" {
  for_each = local.env_map

  name                          = each.value.storage_name
  resource_group_name           = azurerm_resource_group.env[each.key].name
  location                      = azurerm_resource_group.env[each.key].location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = var.enable_private_networking ? false : true
  tags                          = merge(var.tags, { environment = each.key })
}

resource "azurerm_key_vault" "env" {
  for_each = local.env_map

  name                          = each.value.key_vault_name
  location                      = azurerm_resource_group.env[each.key].location
  resource_group_name           = azurerm_resource_group.env[each.key].name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  rbac_authorization_enabled    = true
  public_network_access_enabled = var.enable_private_networking ? false : true
  tags                          = merge(var.tags, { environment = each.key })
}

resource "azurerm_log_analytics_workspace" "env" {
  for_each = local.env_map

  name                = each.value.log_analytics_name
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = merge(var.tags, { environment = each.key })
}

resource "azurerm_application_insights" "env" {
  for_each = local.env_map

  name                = each.value.app_insights_name
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  workspace_id        = azurerm_log_analytics_workspace.env[each.key].id
  application_type    = "web"
  tags                = merge(var.tags, { environment = each.key })
}

resource "azurerm_container_registry" "env" {
  for_each = local.env_map

  name                          = each.value.acr_name
  location                      = azurerm_resource_group.env[each.key].location
  resource_group_name           = azurerm_resource_group.env[each.key].name
  sku                           = var.enable_private_networking ? "Premium" : "Basic"
  admin_enabled                 = false
  public_network_access_enabled = var.enable_private_networking ? false : true
  tags                          = merge(var.tags, { environment = each.key })
}

resource "azapi_resource" "workspace" {
  for_each = local.env_map

  type      = "Microsoft.MachineLearningServices/workspaces@2024-04-01"
  name      = each.value.workspace_name
  parent_id = azurerm_resource_group.env[each.key].id
  location  = azurerm_resource_group.env[each.key].location
  tags      = merge(var.tags, { environment = each.key })

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    sku = {
      name = "Basic"
    }
    properties = {
      storageAccount      = azurerm_storage_account.env[each.key].id
      keyVault            = azurerm_key_vault.env[each.key].id
      containerRegistry   = azurerm_container_registry.env[each.key].id
      applicationInsights = azurerm_application_insights.env[each.key].id
      publicNetworkAccess = var.enable_private_networking ? "Disabled" : "Enabled"
      # With a private ACR, AML cannot use ACR Tasks to build environment
      # images; builds run on this compute cluster instead.
      imageBuildCompute = "cpu-cluster-${each.key}"
    }
  })
}

resource "azapi_resource" "registry" {
  count = var.create_registry ? 1 : 0

  type      = "Microsoft.MachineLearningServices/registries@2024-04-01"
  name      = var.registry_name
  parent_id = azurerm_resource_group.shared[0].id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    properties = {
      # Registry has no private endpoint in this stack; promotion/deployment
      # pipelines on hosted agents reach it over its public endpoint.
      publicNetworkAccess = "Enabled"
      regionDetails = [
        {
          location = var.location
          storageAccountDetails = [
            {
              systemCreatedStorageAccount = {
                storageAccountType       = "Standard_LRS"
                storageAccountHnsEnabled = false
              }
            }
          ]
          acrDetails = [
            {
              systemCreatedAcrAccount = {
                acrAccountSku = "Premium"
              }
            }
          ]
        }
      ]
    }
  })
}

resource "azuredevops_serviceendpoint_azurerm" "arm" {
  count = var.azure_auth_mode == "service_principal_secret" ? 1 : 0

  project_id            = data.azuredevops_project.project.id
  service_endpoint_name = var.service_connection_name
  description           = "Azure service connection for AML platform and delivery."

  credentials {
    serviceprincipalid  = var.service_principal_id
    serviceprincipalkey = var.service_principal_key
  }

  azurerm_spn_tenantid      = var.tenant_id
  azurerm_subscription_id   = var.subscription_id
  azurerm_subscription_name = var.subscription_name
}

# Preferred production target:
# Azure DevOps pipelines use workload identity federation for Azure access.
# The exact Terraform provider path for WIF may vary by provider version and tenant setup,
# so this starter keeps WIF as the documented target while retaining a secret-based fallback resource.

resource "azuredevops_environment" "envs" {
  for_each = toset(var.devops_environments)

  project_id  = data.azuredevops_project.project.id
  name        = each.value
  description = "Managed by Terraform for Azure ML enterprise delivery."
}

resource "azuredevops_variable_group" "shared" {
  for_each = var.variable_group_names

  project_id   = data.azuredevops_project.project.id
  name         = each.value
  description  = "Shared variables for ${each.key} environment."
  allow_access = true

  variable {
    name  = "AZURE_SUBSCRIPTION_ID"
    value = var.subscription_id
  }

  variable {
    name  = "AML_ENVIRONMENT"
    value = each.key
  }

  variable {
    name  = "AML_REGISTRY_NAME"
    value = var.registry_name
  }
}

resource "azuredevops_variable_group" "key_vault_link" {
  for_each = local.create_key_vault_linked_variable_groups ? var.variable_group_names : {}

  project_id   = data.azuredevops_project.project.id
  name         = "${each.value}-kv"
  description  = "Key Vault linked variables for ${each.key} environment."
  allow_access = true

  key_vault {
    name                = azurerm_key_vault.env[each.key].name
    service_endpoint_id = local.key_vault_service_endpoint_id
  }

  variable {
    name = "example-secret"
  }
}

resource "azurerm_private_dns_zone" "blob" {
  count = var.enable_private_networking ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "vault" {
  count = var.enable_private_networking ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  count = var.enable_private_networking ? 1 : 0

  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count = var.enable_private_networking ? 1 : 0

  name                  = "${var.prefix}-blob-link"
  resource_group_name   = azurerm_resource_group.network[0].name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.shared[0].id
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  count = var.enable_private_networking ? 1 : 0

  name                  = "${var.prefix}-vault-link"
  resource_group_name   = azurerm_resource_group.network[0].name
  private_dns_zone_name = azurerm_private_dns_zone.vault[0].name
  virtual_network_id    = azurerm_virtual_network.shared[0].id
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count = var.enable_private_networking ? 1 : 0

  name                  = "${var.prefix}-acr-link"
  resource_group_name   = azurerm_resource_group.network[0].name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.shared[0].id
}

resource "azurerm_private_endpoint" "storage_blob" {
  for_each = var.enable_private_networking ? local.env_map : {}

  name                = "${var.prefix}-${each.key}-stg-pe"
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "${var.prefix}-${each.key}-stg-psc"
    private_connection_resource_id = azurerm_storage_account.env[each.key].id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "blob-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }
}

resource "azurerm_private_endpoint" "key_vault" {
  for_each = var.enable_private_networking ? local.env_map : {}

  name                = "${var.prefix}-${each.key}-kv-pe"
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "${var.prefix}-${each.key}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.env[each.key].id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "vault-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.vault[0].id]
  }
}

resource "azurerm_private_endpoint" "acr" {
  for_each = var.enable_private_networking ? local.env_map : {}

  name                = "${var.prefix}-${each.key}-acr-pe"
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "${var.prefix}-${each.key}-acr-psc"
    private_connection_resource_id = azurerm_container_registry.env[each.key].id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "acr-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }
}

# ---------------------------------------------------------------------------
# Azure ML workspace private endpoints
# Workspaces are created with publicNetworkAccess=Disabled, so pipeline agents
# and any in-VNet client need a workspace private endpoint plus the AML
# private DNS zones to reach the workspace API and data plane.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "aml_api" {
  count = var.enable_private_networking ? 1 : 0

  name                = "privatelink.api.azureml.ms"
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "aml_notebooks" {
  count = var.enable_private_networking ? 1 : 0

  name                = "privatelink.notebooks.azure.net"
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_api" {
  count = var.enable_private_networking ? 1 : 0

  name                  = "${var.prefix}-aml-api-link"
  resource_group_name   = azurerm_resource_group.network[0].name
  private_dns_zone_name = azurerm_private_dns_zone.aml_api[0].name
  virtual_network_id    = azurerm_virtual_network.shared[0].id
}

resource "azurerm_private_dns_zone_virtual_network_link" "aml_notebooks" {
  count = var.enable_private_networking ? 1 : 0

  name                  = "${var.prefix}-aml-notebooks-link"
  resource_group_name   = azurerm_resource_group.network[0].name
  private_dns_zone_name = azurerm_private_dns_zone.aml_notebooks[0].name
  virtual_network_id    = azurerm_virtual_network.shared[0].id
}

resource "azurerm_private_endpoint" "workspace" {
  for_each = var.enable_private_networking ? local.env_map : {}

  name                = "${var.prefix}-${each.key}-ws-pe"
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "${var.prefix}-${each.key}-ws-psc"
    private_connection_resource_id = azapi_resource.workspace[each.key].id
    is_manual_connection           = false
    subresource_names              = ["amlworkspace"]
  }

  private_dns_zone_group {
    name = "aml-dns"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.aml_api[0].id,
      azurerm_private_dns_zone.aml_notebooks[0].id,
    ]
  }
}

# ---------------------------------------------------------------------------
# Self-hosted Azure DevOps agents
# VMSS in the agents subnet, managed by an Azure DevOps elastic pool (Azure
# DevOps installs the agent and scales instances). Subnets created after
# Sep 2025 have no default outbound internet, so a NAT gateway provides the
# egress the agent needs to reach Azure DevOps.
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "agents_nat" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  name                = "${var.prefix}-agents-nat-pip"
  location            = azurerm_resource_group.network[0].location
  resource_group_name = azurerm_resource_group.network[0].name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  name                = "${var.prefix}-agents-nat"
  location            = azurerm_resource_group.network[0].location
  resource_group_name = azurerm_resource_group.network[0].name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.agents[0].id
  public_ip_address_id = azurerm_public_ip.agents_nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  subnet_id      = azurerm_subnet.agents[0].id
  nat_gateway_id = azurerm_nat_gateway.agents[0].id
}

resource "random_password" "agent_admin" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  length  = 24
  special = true
}

resource "azurerm_linux_virtual_machine_scale_set" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  name                = "${var.prefix}-agents-vmss"
  location            = azurerm_resource_group.network[0].location
  resource_group_name = azurerm_resource_group.network[0].name
  sku                 = var.agent_vm_size
  instances           = 0

  admin_username                  = "azdoagent"
  admin_password                  = random_password.agent_admin[0].result
  disable_password_authentication = false

  # Required shape for Azure DevOps elastic pools.
  overprovision          = false
  upgrade_mode           = "Manual"
  single_placement_group = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "agents-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.agents[0].id
    }
  }

  # Ubuntu 22.04 ships Python 3.10; install the Azure CLI and pip for
  # AzureCLI@2 tasks and the AML SDK.
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - python3-pip
      - python3-venv
      - jq
    runcmd:
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    CLOUDINIT
  )

  tags = merge(var.tags, { role = "azdo-agent" })

  lifecycle {
    # The elastic pool controls instance count after creation.
    ignore_changes = [instances, tags]
  }
}

resource "azuredevops_elastic_pool" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled && var.existing_service_endpoint_id != null ? 1 : 0

  name                   = var.agent_pool_name
  service_endpoint_id    = var.existing_service_endpoint_id
  service_endpoint_scope = data.azuredevops_project.project.id
  azure_resource_id      = azurerm_linux_virtual_machine_scale_set.agents[0].id
  project_id             = data.azuredevops_project.project.id

  desired_idle           = var.agent_pool_desired_idle
  max_capacity           = var.agent_pool_max_capacity
  recycle_after_each_use = false
  time_to_live_minutes   = 15
  auto_provision         = false
  auto_update            = true
}

# ---------------------------------------------------------------------------
# AML training compute
# Clusters are VNet-injected (no public node IPs) so nodes resolve and reach
# the private storage/Key Vault/ACR endpoints. The shared NAT gateway gives
# nodes the outbound path they need to the AML control plane.
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "training" {
  count = var.enable_private_networking ? 1 : 0

  name                 = "snet-aml-training"
  resource_group_name  = azurerm_resource_group.network[0].name
  virtual_network_name = azurerm_virtual_network.shared[0].name
  address_prefixes     = [var.training_subnet_prefix]
}

resource "azurerm_subnet_nat_gateway_association" "training" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  subnet_id      = azurerm_subnet.training[0].id
  nat_gateway_id = azurerm_nat_gateway.agents[0].id
}

resource "azurerm_machine_learning_compute_cluster" "cpu" {
  for_each = local.env_map

  name                          = "cpu-cluster-${each.key}"
  location                      = azurerm_resource_group.env[each.key].location
  machine_learning_workspace_id = azapi_resource.workspace[each.key].id
  vm_priority                   = "Dedicated"
  vm_size                       = var.compute_vm_size

  subnet_resource_id     = var.enable_private_networking ? azurerm_subnet.training[0].id : null
  node_public_ip_enabled = var.enable_private_networking ? false : true

  identity {
    type = "SystemAssigned"
  }

  scale_settings {
    min_node_count                       = 0
    max_node_count                       = var.compute_max_nodes
    scale_down_nodes_after_idle_duration = "PT30M"
  }

  tags = merge(var.tags, { environment = each.key })

  depends_on = [
    azurerm_private_endpoint.workspace,
    azurerm_private_endpoint.storage_blob,
    azurerm_subnet_nat_gateway_association.training,
  ]
}

# ---------------------------------------------------------------------------
# Storage file-share private endpoints
# AML workspaces use two storage subresources: blob (job code, artifacts,
# logs) and file (workspace file share). Both need private endpoints when
# public storage access is disabled.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "file" {
  count = var.enable_private_networking ? 1 : 0

  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  count = var.enable_private_networking ? 1 : 0

  name                  = "${var.prefix}-file-link"
  resource_group_name   = azurerm_resource_group.network[0].name
  private_dns_zone_name = azurerm_private_dns_zone.file[0].name
  virtual_network_id    = azurerm_virtual_network.shared[0].id
}

resource "azurerm_private_endpoint" "storage_file" {
  for_each = var.enable_private_networking ? local.env_map : {}

  name                = "${var.prefix}-${each.key}-file-pe"
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  subnet_id           = azurerm_subnet.private_endpoints[0].id

  private_service_connection {
    name                           = "${var.prefix}-${each.key}-file-psc"
    private_connection_resource_id = azurerm_storage_account.env[each.key].id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }

  private_dns_zone_group {
    name                 = "file-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.file[0].id]
  }
}

# ---------------------------------------------------------------------------
# Network security groups
# Baseline segmentation for the compute-bearing subnets. No custom rules are
# needed: attaching an NSG enforces Azure's default posture explicitly
# (VNet traffic allowed, inbound from internet denied, outbound allowed —
# outbound is required for Azure DevOps and the AML control plane).
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  name                = "${var.prefix}-agents-nsg"
  location            = azurerm_resource_group.network[0].location
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "agents" {
  count = var.enable_private_networking && var.self_hosted_agents_enabled ? 1 : 0

  subnet_id                 = azurerm_subnet.agents[0].id
  network_security_group_id = azurerm_network_security_group.agents[0].id
}

resource "azurerm_network_security_group" "training" {
  count = var.enable_private_networking ? 1 : 0

  name                = "${var.prefix}-training-nsg"
  location            = azurerm_resource_group.network[0].location
  resource_group_name = azurerm_resource_group.network[0].name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "training" {
  count = var.enable_private_networking ? 1 : 0

  subnet_id                 = azurerm_subnet.training[0].id
  network_security_group_id = azurerm_network_security_group.training[0].id
}
