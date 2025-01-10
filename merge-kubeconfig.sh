#!/usr/bin/env bash

# Usage:
#   ./merge-kubeconfig.sh /path/to/other/kubeconfig
#
# Description:
#   This script merges the kubeconfig specified as $1 into your default
#   ~/.kube/config. It will remove any duplicate contexts from the
#   incoming kubeconfig before merging.

set -euo pipefail

# Step 1: Validate input
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/kubeconfig"
  exit 1
fi

KUBECONFIG_TO_MERGE="$1"
DEFAULT_KUBECONFIG="${HOME}/.kube/config"

if [[ ! -f "${KUBECONFIG_TO_MERGE}" ]]; then
  echo "Error: '${KUBECONFIG_TO_MERGE}' is not a valid file."
  exit 1
fi

# Step 2: Backup your default kubeconfig
timestamp=$(date "+%d-%m-%Y_%H-%S")
backup_file="${HOME}/.kube/config_backup_${timestamp}"
cp "${DEFAULT_KUBECONFIG}" "${backup_file}"
echo "Created backup of default kubeconfig at: ${backup_file}"

# Step 3: Rename contexts in the file to be merged
temp_file="$(mktemp)"
cp "${KUBECONFIG_TO_MERGE}" "${temp_file}"

export KUBECONFIG="${temp_file}"
merge_contexts=$(kubectl config get-contexts -o name 2>/dev/null || true)

for ctx in ${merge_contexts}; do
  # Get the cluster name associated with the context
  cluster_name=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${ctx}')].context.cluster}")
  
  if [[ -n "${cluster_name}" ]]; then
    new_ctx_name="${cluster_name}"
    echo "Renaming context '${ctx}' to '${new_ctx_name}' in merge file..."
    kubectl config rename-context "${ctx}" "${new_ctx_name}"
  else
    echo "Warning: Could not determine the cluster name for context '${ctx}'. Skipping rename."
  fi
done

# Step 4: Capture existing contexts in the default config
export KUBECONFIG="${DEFAULT_KUBECONFIG}"
existing_contexts=$(kubectl config get-contexts -o name 2>/dev/null || true)

# Step 5: Remove duplicates
export KUBECONFIG="${temp_file}"
for ctx in $(kubectl config get-contexts -o name 2>/dev/null || true); do
  if echo "${existing_contexts}" | grep -q "^${ctx}$"; then
    echo "Context '${ctx}' already exists in default config. Removing from merge file..."
    kubectl config delete-context "${ctx}" 1>/dev/null
  fi
done

# Step 6: Merge the trimmed temp file into the default config
KUBECONFIG="${DEFAULT_KUBECONFIG}:${temp_file}" \
  kubectl config view --flatten > "${HOME}/.kube/config.merged"

mv "${HOME}/.kube/config.merged" "${DEFAULT_KUBECONFIG}"

# Cleanup
rm -f "${temp_file}"

echo "Successfully merged '${KUBECONFIG_TO_MERGE}' into '${DEFAULT_KUBECONFIG}'."
echo "Your old kubeconfig is backed up at: ${backup_file}"
