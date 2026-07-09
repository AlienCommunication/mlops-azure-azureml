# Declarative one-time adoption of pre-existing Azure resources.
#
# Terraform is state-driven: a resource that exists in Azure but not in state
# makes `apply` fail with "already exists". These gated import blocks let an
# operator adopt such resources through the normal plan/apply path (reviewed
# in the plan output, runnable from CI) instead of imperative scripts.
#
# Usage:
#   terraform plan  -var 'bootstrap_adopt=["all"]'          # adopt everything
#   terraform apply -var 'bootstrap_adopt=["all"]'
# or a precise list, e.g.:
#   -var 'bootstrap_adopt=["app_insights", "pe_storage:dev", "vnet"]'
#
# Semantics (verified on Terraform 1.9):
#   - default [] : blocks are inert; fresh setups are unaffected.
#   - target already in state : no-op (idempotent).
#   - target missing in Azure : plan error "Cannot import non-existent remote
#     object" — remove that entry from the list; Terraform will create it.
#
# Azure DevOps objects (environments, variable groups) cannot be adopted here
# because their numeric IDs require a REST lookup; use import_azdo_bootstrap.sh.

locals {
  adopt_all = contains(var.bootstrap_adopt, "all")

  adopt_env_kinds = [
    "resource_groups",
    "storage",
    "key_vault",
    "log_analytics",
    "app_insights",
    "acr",
    "pe_storage",
    "pe_key_vault",
    "pe_acr",
    "workspace",
  ]

  # Per-environment kinds: "storage" adopts every environment,
  # "storage:dev" adopts only dev.
  adopt_envs = {
    for kind in local.adopt_env_kinds :
    kind => toset([
      for env in var.environments : env
      if local.adopt_all || contains(var.bootstrap_adopt, kind) || contains(var.bootstrap_adopt, "${kind}:${env}")
    ])
  }

  adopt_singleton_kinds = [
    "network_rg",
    "vnet",
    "subnet_pe",
    "subnet_agents",
    "dns_blob",
    "dns_vault",
    "dns_acr",
    "dns_link_blob",
    "dns_link_vault",
    "dns_link_acr",
    "shared_rg",
    "registry",
  ]

  adopt_singletons = {
    for kind in local.adopt_singleton_kinds :
    kind => (local.adopt_all || contains(var.bootstrap_adopt, kind)) ? toset([kind]) : toset([])
  }

  network_rg_id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-aml-network"
}

# ---------------------------------------------------------------------------
# Shared network singletons
# ---------------------------------------------------------------------------

import {
  for_each = local.adopt_singletons["network_rg"]
  to       = azurerm_resource_group.network[0]
  id       = local.network_rg_id
}

import {
  for_each = local.adopt_singletons["vnet"]
  to       = azurerm_virtual_network.shared[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/virtualNetworks/${var.prefix}-vnet"
}

import {
  for_each = local.adopt_singletons["subnet_pe"]
  to       = azurerm_subnet.private_endpoints[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/virtualNetworks/${var.prefix}-vnet/subnets/snet-private-endpoints"
}

import {
  for_each = local.adopt_singletons["subnet_agents"]
  to       = azurerm_subnet.agents[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/virtualNetworks/${var.prefix}-vnet/subnets/snet-selfhosted-agents"
}

import {
  for_each = local.adopt_singletons["dns_blob"]
  to       = azurerm_private_dns_zone.blob[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
}

import {
  for_each = local.adopt_singletons["dns_vault"]
  to       = azurerm_private_dns_zone.vault[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
}

import {
  for_each = local.adopt_singletons["dns_acr"]
  to       = azurerm_private_dns_zone.acr[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
}

import {
  for_each = local.adopt_singletons["dns_link_blob"]
  to       = azurerm_private_dns_zone_virtual_network_link.blob[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/${var.prefix}-blob-link"
}

import {
  for_each = local.adopt_singletons["dns_link_vault"]
  to       = azurerm_private_dns_zone_virtual_network_link.vault[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net/virtualNetworkLinks/${var.prefix}-vault-link"
}

import {
  for_each = local.adopt_singletons["dns_link_acr"]
  to       = azurerm_private_dns_zone_virtual_network_link.acr[0]
  id       = "${local.network_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io/virtualNetworkLinks/${var.prefix}-acr-link"
}

import {
  for_each = local.adopt_singletons["shared_rg"]
  to       = azurerm_resource_group.shared[0]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/rg-aml-shared"
}

import {
  for_each = local.adopt_singletons["registry"]
  to       = azapi_resource.registry[0]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/rg-aml-shared/providers/Microsoft.MachineLearningServices/registries/${var.registry_name}?api-version=2024-04-01"
}

# ---------------------------------------------------------------------------
# Per-environment resources
# ---------------------------------------------------------------------------

import {
  for_each = local.adopt_envs["resource_groups"]
  to       = azurerm_resource_group.env[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}"
}

import {
  for_each = local.adopt_envs["storage"]
  to       = azurerm_storage_account.env[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.Storage/storageAccounts/${local.env_map[each.value].storage_name}"
}

import {
  for_each = local.adopt_envs["key_vault"]
  to       = azurerm_key_vault.env[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.KeyVault/vaults/${local.env_map[each.value].key_vault_name}"
}

import {
  for_each = local.adopt_envs["log_analytics"]
  to       = azurerm_log_analytics_workspace.env[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.OperationalInsights/workspaces/${local.env_map[each.value].log_analytics_name}"
}

import {
  for_each = local.adopt_envs["app_insights"]
  to       = azurerm_application_insights.env[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.Insights/components/${local.env_map[each.value].app_insights_name}"
}

import {
  for_each = local.adopt_envs["acr"]
  to       = azurerm_container_registry.env[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.ContainerRegistry/registries/${local.env_map[each.value].acr_name}"
}

import {
  for_each = local.adopt_envs["pe_storage"]
  to       = azurerm_private_endpoint.storage_blob[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.Network/privateEndpoints/${var.prefix}-${each.value}-stg-pe"
}

import {
  for_each = local.adopt_envs["pe_key_vault"]
  to       = azurerm_private_endpoint.key_vault[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.Network/privateEndpoints/${var.prefix}-${each.value}-kv-pe"
}

import {
  for_each = local.adopt_envs["pe_acr"]
  to       = azurerm_private_endpoint.acr[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.Network/privateEndpoints/${var.prefix}-${each.value}-acr-pe"
}

import {
  for_each = local.adopt_envs["workspace"]
  to       = azapi_resource.workspace[each.value]
  id       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.env_map[each.value].resource_group_name}/providers/Microsoft.MachineLearningServices/workspaces/${local.env_map[each.value].workspace_name}?api-version=2024-04-01"
}
