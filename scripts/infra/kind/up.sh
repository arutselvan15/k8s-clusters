#!/usr/bin/env bash
# Day 0 — Kind cluster via Terraform (environments/kind).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AUTO_APPROVE="-auto-approve"

# shellcheck source=scripts/infra/kind/lib.sh
source "${REPO_ROOT}/scripts/infra/kind/lib.sh"

usage() {
  cat <<EOF
Usage: ./scripts/infra/kind/up.sh [-y]

Create the local Kind cluster (terraform environments/kind).
Writes kubeconfig to sensitive/kind/kubeconfig.

-y is accepted for consistency; Kind apply is auto-approved.

Teardown: $(dirname "$0")/down.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -y | --yes)
      AUTO_APPROVE="-auto-approve"
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

ENV_DIR="${K8S_PLAT_KIND_ENV_DIR}"
if [[ ! -d "$ENV_DIR" ]]; then
  echo "Terraform environment not found: $ENV_DIR" >&2
  exit 1
fi

echo "==> Kind: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform kubectl kind
k8s_plat_migrate_to_sensitive
k8s_plat_prepare_kind_runtime

cd "$ENV_DIR"
k8s_plat_kind_terraform_init
# shellcheck disable=SC2086
terraform apply -input=false $AUTO_APPROVE

KUBECONFIG_FILE="$(terraform output -raw kubeconfig_path)"
CLUSTER_NAME="$(terraform output -raw cluster_name)"
echo ""
echo "Cluster ready: ${CLUSTER_NAME} (kind)"
echo "  export KUBECONFIG=${KUBECONFIG_FILE}"
echo "  kubectl get nodes"
echo "  source ${REPO_ROOT}/scripts/lib/kubeconfig-setup.sh ${KUBECONFIG_FILE}"
echo "  Day 1: ${REPO_ROOT}/bootstrap/bootstrap.sh dev"
echo "  Or Day 0+1: ${REPO_ROOT}/scripts/bootstrap/up.sh"
