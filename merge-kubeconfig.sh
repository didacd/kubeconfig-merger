#!/usr/bin/env bash
#
# merge-kubeconfig.sh
#
# Merge an external kubeconfig into your default (~/.kube/config).
#
# Features:
#   1. Backup the default kubeconfig.
#   2. Rename contexts → use cluster name as context name.
#   3. Rename users → <cluster>-<original_user>.
#   4. Check client certificate expiration.
#   5. Remove duplicate contexts.
#   6. Merge safely into ~/.kube/config.
#

set -euo pipefail

# ------------------------------
# Helpers
# ------------------------------
info() { echo "ℹ️  $*"; }
warn() { echo "⚠️  $*" >&2; }
error() {
  echo "❌ $*" >&2
  exit 1
}

# ------------------------------
# Globals
# ------------------------------
DEFAULT_KUBECONFIG="${HOME}/.kube/config"
KUBECONFIG_TO_MERGE="${1:-}"

# ------------------------------
# Functions
# ------------------------------

backup_config() {
  local timestamp
  timestamp=$(date "+%d-%m-%Y_%H-%M-%S")
  local backup_file="${HOME}/.kube/config_backup_${timestamp}"

  cp "${DEFAULT_KUBECONFIG}" "${backup_file}"
  info "Backup created: ${backup_file}"
}

rename_contexts_and_users() {
  local kubeconfig_file="$1"
  export KUBECONFIG="${kubeconfig_file}"

  for ctx in $(kubectl config get-contexts -o name 2>/dev/null || true); do
    local cluster user new_ctx new_user
    cluster=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${ctx}')].context.cluster}")
    user=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${ctx}')].context.user}")

    if [[ -z "${cluster}" || -z "${user}" ]]; then
      warn "Skipping context '${ctx}' (missing cluster or user)."
      continue
    fi

    new_ctx="${cluster}"
    new_user="${cluster}-${user}"

    info "Renaming context '${ctx}' → '${new_ctx}', user → '${new_user}'"

    kubectl config rename-context "${ctx}" "${new_ctx}"

    yq eval -i "
      .users[] |= (select(.name == \"${user}\").name = \"${new_user}\") |
      .contexts[] |= (select(.name == \"${new_ctx}\").context.user = \"${new_user}\")
    " "${kubeconfig_file}"

    check_certificate "${kubeconfig_file}" "${new_user}"
  done
}

check_certificate() {
  local kubeconfig_file="$1"
  local user="$2"

  local cert_file cert_data
  cert_file=$(yq eval ".users[] | select(.name==\"${user}\").user[\"client-certificate\"]" "${kubeconfig_file}")
  cert_data=$(yq eval ".users[] | select(.name==\"${user}\").user[\"client-certificate-data\"]" "${kubeconfig_file}")

  if [[ "${cert_file}" != "null" && -f "${cert_file}" ]]; then
    info "Checking certificate for ${user} (from file: ${cert_file})"
    openssl x509 -in "${cert_file}" -noout -dates
  elif [[ "${cert_data}" != "null" ]]; then
    info "Checking embedded certificate for ${user}"
    echo "${cert_data}" | base64 -d | openssl x509 -noout -dates
  else
    warn "No client certificate found for user '${user}'."
  fi
}

remove_duplicates() {
  local kubeconfig_file="$1"

  export KUBECONFIG="${DEFAULT_KUBECONFIG}"
  local existing
  existing=$(kubectl config get-contexts -o name 2>/dev/null || true)

  export KUBECONFIG="${kubeconfig_file}"
  for ctx in $(kubectl config get-contexts -o name 2>/dev/null || true); do
    if echo "${existing}" | grep -q "^${ctx}$"; then
      warn "Removing duplicate context '${ctx}' from merge file."
      kubectl config delete-context "${ctx}" >/dev/null
    fi
  done
}

merge_configs() {
  local kubeconfig_file="$1"
  KUBECONFIG="${DEFAULT_KUBECONFIG}:${kubeconfig_file}" \
    kubectl config view --flatten >"${HOME}/.kube/config.merged"

  mv "${HOME}/.kube/config.merged" "${DEFAULT_KUBECONFIG}"
  info "Merge completed. Default kubeconfig updated."
}

# ------------------------------
# Main
# ------------------------------
main() {
  [[ -z "${KUBECONFIG_TO_MERGE}" ]] && error "Usage: $0 /path/to/kubeconfig"
  [[ ! -f "${KUBECONFIG_TO_MERGE}" ]] && error "File not found: ${KUBECONFIG_TO_MERGE}"

  backup_config

  local tmp
  tmp="$(mktemp)"
  cp "${KUBECONFIG_TO_MERGE}" "${tmp}"

  rename_contexts_and_users "${tmp}"
  remove_duplicates "${tmp}"
  merge_configs "${tmp}"

  rm -f "${tmp}"
  info "All done ✅"
}

main "$@"
