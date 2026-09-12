#!/usr/bin/env bash
#
# Day 0 dispatcher.
#   ./scripts/infra/down.sh
#   ./scripts/infra/down.sh aws -y

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="kind"
YES=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [kind|aws|openstack] [-y]

  kind         ./scripts/infra/kind/down.sh
  aws          ./scripts/infra/aws/down.sh
  openstack    ./scripts/infra/openstack/down.sh

  -y, --yes   pass through (terraform destroy -auto-approve on aws/openstack)
  -h, --help
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
    kind | aws | openstack)
      PLATFORM="$1"
      ;;
    *)
      echo "Unknown argument: $1 (use kind, aws, or openstack)" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

exec "${REPO_ROOT}/scripts/infra/${PLATFORM}/down.sh" ${YES}
