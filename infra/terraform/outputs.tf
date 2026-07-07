output "resource_groups" {
  value = {
    for env, rg in azurerm_resource_group.env : env => rg.name
  }
}

output "workspaces" {
  value = {
    for env, ws in azapi_resource.workspace : env => ws.name
  }
}

output "service_connection_name" {
  value = var.azure_auth_mode == "service_principal_secret" ? azuredevops_serviceendpoint_azurerm.arm[0].service_endpoint_name : var.service_connection_name
}

output "network_resource_group" {
  value = var.enable_private_networking ? azurerm_resource_group.network[0].name : null
}

output "shared_vnet_name" {
  value = var.enable_private_networking ? azurerm_virtual_network.shared[0].name : null
}

output "azure_devops_environments" {
  value = [for env in azuredevops_environment.envs : env.name]
}

output "variable_groups" {
  value = {
    shared   = [for vg in azuredevops_variable_group.shared : vg.name]
    keyvault = [for vg in azuredevops_variable_group.key_vault_link : vg.name]
  }
}
