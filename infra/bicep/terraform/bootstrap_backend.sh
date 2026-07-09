#!/usr/bin/env bash

set -euo pipefail

# Idempotent bootstrap for the Terraform remote-state backend.
# Safe to run repeatedly: existing resources are left untouched.
#
# Run this ONCE per tenant BEFORE the first `terraform init`.
# Requires: az CLI logged in (`az login`) with rights to create a
# resource group and storage account in the target subscription.
#
# NOTE: storage account names are globally unique across all of Azure.
# A fresh tenant setup MUST override TF_BACKEND_STORAGE_ACCOUNT.

RG="${TF_BACKEND_RESOURCE_GROUP:-rg-usedcar-tfstate}"
SA="${TF_BACKEND_STORAGE_ACCOUNT:-stusedcartfstate01}"
CONTAINER="${TF_BACKEND_CONTAINER:-tfstate}"
LOCATION="${TF_BACKEND_LOCATION:-eastus}"

echo "Backend target: rg=$RG storage=$SA container=$CONTAINER location=$LOCATION"

az group create --name "$RG" --location "$LOCATION" --output none
echo "Resource group ready: $RG"

if az storage account show --name "$SA" --resource-group "$RG" --output none 2>/dev/null; then
  echo "Storage account already exists: $SA"
else
  az storage account create \
    --name "$SA" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku Standard_GRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
  echo "Storage account created: $SA"
fi

# Blob versioning protects the state file against accidental corruption.
az storage account blob-service-properties update \
  --account-name "$SA" \
  --resource-group "$RG" \
  --enable-versioning true \
  --output none

if az storage container show --name "$CONTAINER" --account-name "$SA" --auth-mode login --output none 2>/dev/null; then
  echo "Container already exists: $CONTAINER"
else
  az storage container create --name "$CONTAINER" --account-name "$SA" --auth-mode login --output none 2>/dev/null \
    || az storage container create --name "$CONTAINER" --account-name "$SA" --output none
  echo "Container created: $CONTAINER"
fi

cat <<EOF

Backend is ready. Initialize Terraform with:

  terraform init \\
    -backend-config="resource_group_name=$RG" \\
    -backend-config="storage_account_name=$SA" \\
    -backend-config="container_name=$CONTAINER" \\
    -backend-config="key=azureml-enterprise.tfstate"

And set the same four values in the Azure DevOps variable group 'aml-infra-tfvars'
as TF_BACKEND_RESOURCE_GROUP / TF_BACKEND_STORAGE_ACCOUNT / TF_BACKEND_CONTAINER / TF_BACKEND_KEY.
EOF
