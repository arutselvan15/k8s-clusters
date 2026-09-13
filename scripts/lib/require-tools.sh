#!/bin/bash
# Standalone CLI: verify commands exist on PATH.
#
#   ./scripts/lib/require-tools.sh kubectl terraform kind
#
# Other scripts invoke this with their required tool list; it is not sourced.

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [command ...]

Exit 0 if every command is on PATH; otherwise print missing names and exit 1.

Example:
  $(basename "$0") kubectl terraform kind
EOF
}

tool_hint() {
  case "$1" in
    terraform)
      echo "Install Terraform >= 1.5 (e.g. brew tap hashicorp/tap && brew install hashicorp/tap/terraform)" >&2
      ;;
    kind)
      echo "Install Kind (e.g. brew install kind)" >&2
      ;;
    kubectl)
      echo "Install kubectl (e.g. brew install kubectl)" >&2
      ;;
    aws)
      echo "Install AWS CLI v2 (e.g. brew install awscli)" >&2
      ;;
    openstack)
      echo "Install python-openstackclient if you want CLI checks (optional; Terraform uses clouds.yaml)" >&2
      ;;
  esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

missing=0
tool=""
for tool in "$@"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool not found: $tool" >&2
    tool_hint "$tool"
    missing=1
  fi
done

exit "$missing"
