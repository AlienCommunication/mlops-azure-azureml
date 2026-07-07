variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "subscription_name" {
  description = "Azure subscription display name."
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Resource naming prefix."
  type        = string
  default     = "usedcar"
}

variable "enable_private_networking" {
  description = "Enable private networking foundations for storage, Key Vault, and ACR."
  type        = bool
  default     = true
}

variable "self_hosted_agents_enabled" {
  description = "Whether the design assumes self-hosted Azure DevOps agents."
  type        = bool
  default     = true
}

variable "vnet_address_space" {
  description = "Address space for the shared VNet."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "private_endpoints_subnet_prefix" {
  description = "Subnet prefix for private endpoints."
  type        = string
  default     = "10.20.1.0/24"
}

variable "agents_subnet_prefix" {
  description = "Subnet prefix for self-hosted Azure DevOps agents."
  type        = string
  default     = "10.20.2.0/24"
}

variable "tags" {
  description = "Common Azure tags."
  type        = map(string)
  default = {
    project = "azure-mlops"
  }
}

variable "environments" {
  description = "Environment list."
  type        = list(string)
  default     = ["dev", "test", "prod"]
}

variable "registry_name" {
  description = "Azure ML registry name."
  type        = string
  default     = "aml-enterprise-registry"
}

variable "create_registry" {
  description = "Whether to create the Azure ML registry."
  type        = bool
  default     = true
}

variable "azure_devops_org_service_url" {
  description = "Azure DevOps organization URL."
  type        = string
}

variable "azure_devops_project_name" {
  description = "Azure DevOps project name."
  type        = string
}

variable "azure_devops_pat" {
  description = "Azure DevOps personal access token for Terraform bootstrap."
  type        = string
  sensitive   = true
}

variable "service_connection_name" {
  description = "Azure DevOps ARM service connection name."
  type        = string
  default     = "az-mlops-sc"
}

variable "existing_service_endpoint_id" {
  description = "Existing Azure DevOps service connection ID to use for Key Vault-linked variable groups when the service connection is not created by this Terraform stack."
  type        = string
  default     = null
}

variable "azure_auth_mode" {
  description = "Azure auth mode for Azure DevOps pipeline access. Preferred: workload_identity_federation."
  type        = string
  default     = "workload_identity_federation"
}

variable "service_principal_id" {
  description = "Service principal client ID used by the ARM service connection."
  type        = string
}

variable "service_principal_key" {
  description = "Service principal secret used by the ARM service connection."
  type        = string
  sensitive   = true
}

variable "devops_environments" {
  description = "Azure DevOps environment names."
  type        = list(string)
  default     = ["aml-test-approval", "aml-test", "aml-prod"]
}

variable "variable_group_names" {
  description = "Azure DevOps variable group names."
  type = map(string)
  default = {
    dev  = "aml-dev-shared"
    test = "aml-test-shared"
    prod = "aml-prod-shared"
  }
}
