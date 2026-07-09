#!/usr/bin/env bash

set -euo pipefail

# One-time adoption helper for Azure DevOps objects (environments, variable
# groups) that already exist in the project but are not in Terraform state.
#
# Azure resources are NOT handled here anymore: adopt those declaratively with
# the gated import blocks in imports.tf, e.g.
#   terraform apply -var 'bootstrap_adopt=["all"]'
#
# This script only remains because Azure DevOps import IDs are numeric and must
# be looked up via the REST API, which import blocks cannot express.
#
# Requires: AZURE_DEVOPS_EXT_PAT exported with read access to environments and
# variable groups.

AZDO_ORG_URL="${TF_VAR_azure_devops_org_service_url:-https://dev.azure.com/genaidevops0}"
AZDO_PROJECT="${TF_VAR_azure_devops_project_name:-mlops1}"
AZDO_PROJECT_ID="${AZDO_PROJECT_ID:-cc7dd0c6-8a2b-487c-a094-2f4ead2848e3}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd terraform
require_cmd curl
require_cmd python3

if [[ -z "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then
  echo "AZURE_DEVOPS_EXT_PAT is not set. Export a PAT with read access to" >&2
  echo "environments and variable groups, then rerun." >&2
  exit 1
fi

json_get_first_id() {
  local url="$1"
  curl -sS -u ":${AZURE_DEVOPS_EXT_PAT}" "$url" | python3 -c 'import json,sys; data=json.load(sys.stdin); value=data.get("value", []); print(value[0]["id"] if value else "")'
}

json_get_first_id_from_array() {
  local url="$1"
  local field="$2"
  local expected="$3"
  curl -sS -u ":${AZURE_DEVOPS_EXT_PAT}" "$url" | python3 -c 'import json,sys; data=json.load(sys.stdin); field=sys.argv[1]; expected=sys.argv[2]; value=data.get("value", []); match=next((item for item in value if item.get(field)==expected), None); print(match["id"] if match else "")' "$field" "$expected"
}

import_if_missing() {
  local address="$1"
  local id="$2"

  if terraform state show "$address" >/dev/null 2>&1; then
    echo "Skipping already-managed resource: $address"
    return 0
  fi

  echo "Importing $address"
  terraform import "$address" "$id"
}

echo "Importing pre-existing Azure DevOps resources..."

aml_test_env_id="$(json_get_first_id "${AZDO_ORG_URL}/${AZDO_PROJECT}/_apis/distributedtask/environments?name=aml-test&api-version=7.1-preview.1")"
aml_test_approval_env_id="$(json_get_first_id "${AZDO_ORG_URL}/${AZDO_PROJECT}/_apis/distributedtask/environments?name=aml-test-approval&api-version=7.1-preview.1")"
aml_prod_env_id="$(json_get_first_id "${AZDO_ORG_URL}/${AZDO_PROJECT}/_apis/distributedtask/environments?name=aml-prod&api-version=7.1-preview.1")"

aml_dev_shared_id="$(json_get_first_id_from_array "${AZDO_ORG_URL}/${AZDO_PROJECT}/_apis/distributedtask/variablegroups?groupName=aml-dev-shared&api-version=7.1-preview.2" "name" "aml-dev-shared")"
aml_test_shared_id="$(json_get_first_id_from_array "${AZDO_ORG_URL}/${AZDO_PROJECT}/_apis/distributedtask/variablegroups?groupName=aml-test-shared&api-version=7.1-preview.2" "name" "aml-test-shared")"
aml_prod_shared_id="$(json_get_first_id_from_array "${AZDO_ORG_URL}/${AZDO_PROJECT}/_apis/distributedtask/variablegroups?groupName=aml-prod-shared&api-version=7.1-preview.2" "name" "aml-prod-shared")"

[[ -n "${aml_test_env_id}" ]] && import_if_missing 'azuredevops_environment.envs["aml-test"]' "${AZDO_PROJECT_ID}/${aml_test_env_id}"
[[ -n "${aml_test_approval_env_id}" ]] && import_if_missing 'azuredevops_environment.envs["aml-test-approval"]' "${AZDO_PROJECT_ID}/${aml_test_approval_env_id}"
[[ -n "${aml_prod_env_id}" ]] && import_if_missing 'azuredevops_environment.envs["aml-prod"]' "${AZDO_PROJECT_ID}/${aml_prod_env_id}"
[[ -n "${aml_dev_shared_id}" ]] && import_if_missing 'azuredevops_variable_group.shared["dev"]' "${AZDO_PROJECT_ID}/${aml_dev_shared_id}"
[[ -n "${aml_test_shared_id}" ]] && import_if_missing 'azuredevops_variable_group.shared["test"]' "${AZDO_PROJECT_ID}/${aml_test_shared_id}"
[[ -n "${aml_prod_shared_id}" ]] && import_if_missing 'azuredevops_variable_group.shared["prod"]' "${AZDO_PROJECT_ID}/${aml_prod_shared_id}"

echo "Import pass complete. Run 'terraform plan' next."
