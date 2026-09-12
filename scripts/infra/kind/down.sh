#!/usr/bin/env bash
# Day 0 — destroy Kind cluster via Terraform (environments/kind).

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
Usage: ./scripts/infra/kind/down.sh [cluster] [-y]

Destroy the local Kind cluster (terraform environments/kind).
Same config id as up.
Kind destroy is auto-approved; -y is accepted for consistency.

  ./scripts/infra/down.sh kind
  ./scripts/infra/down.sh kind k8s-kind
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

if [[ ! -f "${K8S_PLAT_TFSTATE}" && ! -d "${ENV_DIR}/.terraform" ]]; then
  echo "No Terraform state for Kind; nothing to destroy."
  k8s_plat_purge_cluster_outputs
  exit 0
fi

echo "==> Destroy Kind cluster ${K8S_PLAT_CLUSTER_NAME}: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform
k8s_plat_migrate_to_sensitive
k8s_plat_prepare_kind_runtime

cd "$ENV_DIR"
k8s_plat_kind_terraform_init
# shellcheck disable=SC2086
terraform destroy -input=false $AUTO_APPROVE "${K8S_TF_VAR_ARGS[@]}"

k8s_plat_purge_cluster_outputs
echo "Kind cluster destroyed."
