terraform {
  # 1.7+ is required for `import` blocks with for_each (see imports.tf).
  required_version = ">= 1.7.0"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.14"
    }

    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
