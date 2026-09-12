#!/usr/bin/env bash
#
# Day 0 dispatcher. One Terraform environment per backend.
#   ./scripts/infra/up.sh kind
#   ./scripts/infra/up.sh aws [cluster]
#   ./scripts/infra/up.sh openstack [cluster]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="kind"
YES=""
CLUSTER=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [kind|aws|openstack] [cluster] [-y]

  kind         ./scripts/infra/kind/up.sh
  aws          ./scripts/infra/aws/up.sh [cluster]
  openstack    ./scripts/infra/openstack/up.sh [cluster]

  cluster     config id or path (required for aws/openstack)
              Directory under clusters/<platform>/, e.g. k8s-aws

  -y, --yes   pass through to the platform script
  -h, --help

Build always applies exactly one cluster config.

Day 0 + Day 1 (Kind): ./scripts/bootstrap/up.sh
Teardown: $(dirname "$0")/down.sh [kind|aws|openstack] [cluster]
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
  exec "${REPO_ROOT}/scripts/infra/kind/up.sh" ${YES}
fi

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"
k8s_plat_require_cluster_spec "${PLATFORM}" "${CLUSTER}" || exit 1
exec "${REPO_ROOT}/scripts/infra/${PLATFORM}/up.sh" ${YES} --cluster "${CLUSTER}"
