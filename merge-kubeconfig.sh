#!/usr/bin/env bash
#
# merge-kubeconfig.sh
#
# Merge an external kubeconfig into your default (~/.kube/config).
#
# Features:
#   1. Backup the default kubeconfig.
#   2. Use standard kubectl merge flow.
#   3. Write merged output to a temporary file first.
#   4. Validate merged kubeconfig before replacing destination.
#   5. Atomically replace ~/.kube/config only on success.
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
BACKUP_FILE=""
MERGED_TMP_FILE=""

# ------------------------------
# Functions
# ------------------------------

backup_config() {
  [[ ! -f "${DEFAULT_KUBECONFIG}" ]] && return

  local timestamp
  timestamp=$(date "+%d-%m-%Y_%H-%M-%S")
  BACKUP_FILE="${HOME}/.kube/config_backup_${timestamp}"

  cp -p "${DEFAULT_KUBECONFIG}" "${BACKUP_FILE}"
  chmod 600 "${BACKUP_FILE}"
  info "Backup created: ${BACKUP_FILE}"
}

cleanup() {
  if [[ -n "${MERGED_TMP_FILE}" && -f "${MERGED_TMP_FILE}" ]]; then
    rm -f "${MERGED_TMP_FILE}"
  fi
}

merge_and_install_config() {
  local kubeconfig_file="$1"
  MERGED_TMP_FILE="$(mktemp "${HOME}/.kube/config.merged.XXXXXX")"

  KUBECONFIG="${DEFAULT_KUBECONFIG}:${kubeconfig_file}" \
    kubectl config view --merge --flatten >"${MERGED_TMP_FILE}"

  [[ ! -s "${MERGED_TMP_FILE}" ]] && error "Merged kubeconfig is empty. Verify the incoming kubeconfig file is valid."
  if ! kubectl --kubeconfig="${MERGED_TMP_FILE}" config view >/dev/null 2>&1; then
    error "Merged kubeconfig validation failed."
  fi

  chmod 600 "${MERGED_TMP_FILE}"
  mv "${MERGED_TMP_FILE}" "${DEFAULT_KUBECONFIG}"
  MERGED_TMP_FILE=""
  info "Merge completed. Default kubeconfig updated safely."
}

# ------------------------------
# Main
# ------------------------------
main() {
  [[ -z "${KUBECONFIG_TO_MERGE}" ]] && error "Usage: $0 /path/to/kubeconfig"
  [[ ! -f "${KUBECONFIG_TO_MERGE}" ]] && error "File not found: ${KUBECONFIG_TO_MERGE}"

  trap cleanup EXIT
  mkdir -p "${HOME}/.kube"

  backup_config
  if [[ ! -f "${DEFAULT_KUBECONFIG}" ]]; then
    touch "${DEFAULT_KUBECONFIG}"
    chmod 600 "${DEFAULT_KUBECONFIG}"
  fi

  merge_and_install_config "${KUBECONFIG_TO_MERGE}"
  info "All done ✅"
}

main "$@"
