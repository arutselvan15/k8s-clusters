#!/usr/bin/env bash
# Day 0 — destroy Kind cluster via Terraform (environments/kind).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
AUTO_APPROVE="-auto-approve"

# shellcheck source=scripts/infra/kind/lib.sh
source "${REPO_ROOT}/scripts/infra/kind/lib.sh"

usage() {
  cat <<EOF
Usage: ./scripts/infra/kind/down.sh [-y]

Destroy the local Kind cluster (terraform environments/kind).
Kind destroy is auto-approved; -y is accepted for consistency.
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

if [[ ! -f "${K8S_PLAT_KIND_TFSTATE}" && ! -d "${ENV_DIR}/.terraform" ]]; then
  echo "No Terraform state for Kind; nothing to destroy."
  exit 0
fi

echo "==> Destroy Kind: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform
k8s_plat_migrate_to_sensitive
k8s_plat_prepare_kind_runtime

cd "$ENV_DIR"
k8s_plat_kind_terraform_init
# shellcheck disable=SC2086
terraform destroy -input=false $AUTO_APPROVE

if [[ -f "${K8S_PLAT_KIND_KUBECONFIG}" ]]; then
  rm -f "${K8S_PLAT_KIND_KUBECONFIG}"
  echo "Removed ${K8S_PLAT_KIND_KUBECONFIG}"
fi

echo "Kind cluster destroyed."
