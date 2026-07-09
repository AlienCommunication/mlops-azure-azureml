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

variable "enable_key_vault_linked_variable_groups" {
  description = "Whether Terraform should create Azure DevOps Key Vault-linked variable groups during bootstrap."
  type        = bool
  default     = false
}

variable "service_principal_id" {
  description = "Service principal client ID used by the ARM service connection. Only required when azure_auth_mode is service_principal_secret."
  type        = string
  default     = null
}

variable "service_principal_key" {
  description = "Service principal secret used by the ARM service connection. Only required when azure_auth_mode is service_principal_secret."
  type        = string
  sensitive   = true
  default     = null
}

variable "training_subnet_prefix" {
  description = "Subnet prefix for VNet-injected AML compute clusters."
  type        = string
  default     = "10.20.3.0/24"
}

variable "compute_vm_size" {
  description = "VM size for AML training compute clusters."
  type        = string
  default     = "STANDARD_DS3_V2"
}

variable "compute_max_nodes" {
  description = "Maximum node count per AML compute cluster."
  type        = number
  default     = 2
}

variable "agent_vm_size" {
  description = "VM size for the self-hosted Azure DevOps agent scale set."
  type        = string
  default     = "Standard_B2ms"
}

variable "agent_pool_name" {
  description = "Azure DevOps elastic agent pool name backed by the agent VMSS."
  type        = string
  default     = "aml-selfhosted-agents"
}

variable "agent_pool_max_capacity" {
  description = "Maximum number of agent VMs the elastic pool may scale to."
  type        = number
  default     = 2
}

variable "agent_pool_desired_idle" {
  description = "Number of idle agents to keep warm. 0 scales to zero (cheapest; first job waits a few minutes for a VM)."
  type        = number
  default     = 0
}

variable "bootstrap_adopt" {
  description = "One-time adoption list for resources that already exist in Azure but are not yet in Terraform state. Empty (default) on fresh setups. Use [\"all\"], kind names (e.g. \"storage\"), or kind:env entries (e.g. \"storage:dev\"). See imports.tf."
  type        = set(string)
  default     = []
}

variable "devops_environments" {
  description = "Azure DevOps environment names."
  type        = list(string)
  default     = ["aml-test-approval", "aml-test", "aml-prod"]
}

variable "variable_group_names" {
  description = "Azure DevOps variable group names."
  type        = map(string)
  default = {
    dev  = "aml-dev-shared"
    test = "aml-test-shared"
    prod = "aml-prod-shared"
  }
}
