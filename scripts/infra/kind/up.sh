#!/usr/bin/env bash
# Day 0 — Kind cluster via Terraform (environments/kind).

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AUTO_APPROVE="-auto-approve"
CLUSTER_SPEC=""

# shellcheck source=scripts/infra/kind/lib.sh
source "${REPO_ROOT}/scripts/infra/kind/lib.sh"

usage() {
  cat <<EOF
Usage: ./scripts/infra/kind/up.sh [cluster] [-y]

Create the local Kind cluster (terraform environments/kind).
Config: clusters/kind/<id>/config.yaml.
Writes kubeconfig to sensitive/kind/<cluster_name>/kubeconfig.

-y is accepted for consistency; Kind apply is auto-approved.

  ./scripts/infra/up.sh kind
  ./scripts/infra/up.sh kind k8s-kind

Teardown: ./scripts/infra/down.sh kind
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
    -c | --cluster)
      CLUSTER_SPEC="${2:?cluster config required}"
      shift
      ;;
    *)
      CLUSTER_SPEC="$1"
      ;;
  esac
  shift
done

ENV_DIR="${K8S_PLAT_KIND_ENV_DIR}"
if [[ ! -d "$ENV_DIR" ]]; then
  echo "Terraform environment not found: $ENV_DIR" >&2
  exit 1
fi

CLUSTER_SPEC="$(k8s_plat_effective_cluster_spec kind "${CLUSTER_SPEC}")" || exit 1
k8s_plat_kind_bind "${CLUSTER_SPEC}"
k8s_plat_load_kind_vars

echo "==> Kind: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform kubectl kind
k8s_plat_migrate_to_sensitive
k8s_plat_prepare_kind_runtime

cd "$ENV_DIR"
k8s_plat_kind_terraform_init
# shellcheck disable=SC2086
terraform apply -input=false $AUTO_APPROVE "${K8S_TF_VAR_ARGS[@]}"

KUBECONFIG_FILE="$(terraform output -raw kubeconfig_path)"
CLUSTER_NAME="$(terraform output -raw cluster_name)"
echo ""
echo "Cluster ready: ${CLUSTER_NAME} (kind)"
echo "  export KUBECONFIG=${KUBECONFIG_FILE}"
echo "  kubectl get nodes"
echo "  source ${REPO_ROOT}/scripts/lib/kubeconfig-setup.sh ${KUBECONFIG_FILE}"
echo "  Day 1: ${REPO_ROOT}/bootstrap/bootstrap.sh dev"
echo "  Or Day 0+1: ${REPO_ROOT}/scripts/bootstrap/up.sh"
