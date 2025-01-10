#!/usr/bin/env bash

# Usage:
#   ./merge-kubeconfig.sh /path/to/other/kubeconfig
#
# Description:
#   This script merges the kubeconfig specified as $1 into your default
#   ~/.kube/config. It will remove any duplicate contexts from the
#   incoming kubeconfig before merging.

set -euo pipefail

# Validate input
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/kubeconfig"
  exit 1
fi

KUBECONFIG_TO_MERGE="$1"
DEFAULT_KUBECONFIG="$HOME/.kube/config"

if [[ ! -f "$KUBECONFIG_TO_MERGE" ]]; then
  echo "Error: '$KUBECONFIG_TO_MERGE' is not a valid file."
  exit 1
fi

# Step 2: Capture existing contexts in the default config
export KUBECONFIG="$DEFAULT_KUBECONFIG"
existing_contexts=$(kubectl config get-contexts -o name 2>/dev/null || true)

# Step 3: Create a temp file and copy the kubeconfig to merge
temp_file="$(mktemp)"
cp "$KUBECONFIG_TO_MERGE" "$temp_file"

# Point kubectl to the temp file
export KUBECONFIG="$temp_file"
merge_contexts=$(kubectl config get-contexts -o name 2>/dev/null || true)

# Step 4: Remove any context that already exists in default config
for ctx in $merge_contexts; do
  if echo "$existing_contexts" | grep -q "^$ctx$"; then
    echo "Context '$ctx' already exists in default config. Removing from merge file..."
    # Delete the context in the temp file
    kubectl config delete-context "$ctx" 1>/dev/null

    # Optional (more advanced): 
    # If the cluster or user is not referenced by any other context in this temp file,
    # you may also want to remove them:
    #   kubectl config delete-cluster <cluster-name>
    #   kubectl config unset users.<user-name>
  fi
done

# Step 5: Merge the trimmed temp file into the default config
# Re-point KUBECONFIG to include both files
KUBECONFIG="$DEFAULT_KUBECONFIG:$temp_file" \
  kubectl config view --flatten > "$HOME/.kube/config.merged"

# Overwrite the default config with the merged result
mv "$HOME/.kube/config.merged" "$DEFAULT_KUBECONFIG"

# Cleanup
rm -f "$temp_file"

echo "Successfully merged '$KUBECONFIG_TO_MERGE' into '$DEFAULT_KUBECONFIG'."
