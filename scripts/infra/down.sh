#!/usr/bin/env bash
#
# Day 0 dispatcher.
#   ./scripts/infra/down.sh kind
#   ./scripts/infra/down.sh aws [cluster] -y

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="kind"
YES=""
CLUSTER=""

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [kind|aws|openstack] [cluster] [-y]

  kind         ./scripts/infra/kind/down.sh
  aws          ./scripts/infra/aws/down.sh [cluster]
  openstack    ./scripts/infra/openstack/down.sh [cluster]

  cluster     same config id used at up (required for aws/openstack)
  -y, --yes   terraform destroy -auto-approve on aws/openstack
  -h, --help

After destroy, prompts to push sensitive/ to S3 with prune.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -y | --yes)
      YES="-y"
      ;;
    -c | --cluster)
      CLUSTER="${2:?cluster config required}"
      shift
      ;;
    kind | aws | openstack)
      PLATFORM="$1"
      ;;
    *)
      if [[ -z "${CLUSTER}" ]]; then
        CLUSTER="$1"
      else
        echo "Unknown argument: $1 (use kind, aws, or openstack)" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ "${PLATFORM}" == "kind" ]]; then
  # shellcheck disable=SC2086
  "${REPO_ROOT}/scripts/infra/kind/down.sh" ${YES}
  k8s_plat_s3_offer
  exit 0
fi

# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"
k8s_plat_require_cluster_spec "${PLATFORM}" "${CLUSTER}" || exit 1
# shellcheck disable=SC2086
"${REPO_ROOT}/scripts/infra/${PLATFORM}/down.sh" ${YES} --cluster "${CLUSTER}"
k8s_plat_s3_offer
