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

  create_key_vault_linked_variable_groups = local.key_vault_service_endpoint_id != null
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

resource "azurerm_storage_account" "env" {
  for_each = local.env_map

  name                     = each.value.storage_name
  resource_group_name      = azurerm_resource_group.env[each.key].name
  location                 = azurerm_resource_group.env[each.key].location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  public_network_access_enabled = var.enable_private_networking ? false : true
  tags                     = merge(var.tags, { environment = each.key })
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

  name                = each.value.acr_name
  location            = azurerm_resource_group.env[each.key].location
  resource_group_name = azurerm_resource_group.env[each.key].name
  sku                 = "Basic"
  admin_enabled       = false
  public_network_access_enabled = var.enable_private_networking ? false : true
  tags                = merge(var.tags, { environment = each.key })
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
    }
  })
}

resource "azapi_resource" "registry" {
  count = var.create_registry ? 1 : 0

  type      = "Microsoft.MachineLearningServices/registries@2024-04-01"
  name      = var.registry_name
  parent_id = "/subscriptions/${var.subscription_id}"
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    sku = {
      name = "Basic"
    }
    properties = {}
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
