provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azapi" {
}

provider "azuredevops" {
  org_service_url       = var.azure_devops_org_service_url
  personal_access_token = var.azure_devops_pat
}
