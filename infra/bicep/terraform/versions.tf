terraform {
  required_version = ">= 1.6.0"

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
  }
}
