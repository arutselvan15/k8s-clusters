#!/bin/bash

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [overlay]

Day 1 — installs or upgrades Argo CD on the cluster from the current shell.
Safe to re-run.

Overlay: dev, stg, prod (optional; default from bootstrap/env or dev).
Environment is loaded in argocd/install.sh (bootstrap/env/).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${2:-}" ]]; then
  echo "Unexpected argument: $2" >&2
  usage >&2
  exit 1
fi

echo "==> Day 1: Argo CD"
"$SCRIPT_DIR/argocd/install.sh" "${1:-}"

echo ""
echo "Day 1 complete."
echo "  kubectl get pods -n argocd"
echo "  Day 2: ./scripts/gitops/start.sh <profile>  (see gitops/README.md)"
