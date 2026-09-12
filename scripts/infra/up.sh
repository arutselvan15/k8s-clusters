#!/usr/bin/env bash
#
# Day 0 dispatcher. One Terraform environment per backend.
#   ./scripts/infra/up.sh
#   ./scripts/infra/up.sh kind
#   ./scripts/infra/up.sh aws
#   ./scripts/infra/up.sh openstack

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="kind"
YES=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [kind|aws|openstack] [-y]

  kind         ./scripts/infra/kind/up.sh  → terraform environments/kind (default)
  aws          ./scripts/infra/aws/up.sh   → terraform environments/ec2
  openstack    ./scripts/infra/openstack/up.sh → terraform environments/openstack

  -y, --yes   pass through to the platform script
  -h, --help

Day 0 + Day 1 (Kind): ./scripts/bootstrap/up.sh
Teardown: $(dirname "$0")/down.sh [kind|aws|openstack]
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

exec "${REPO_ROOT}/scripts/infra/${PLATFORM}/up.sh" ${YES}
