#!/bin/bash

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Day 1 — installs or upgrades Argo CD on the cluster from the current shell.
Safe to re-run.

Helm values: bootstrap/argocd/values.yaml
Secrets: sensitive/bootstrap/bootstrap.env
Optional Helm extra: sensitive/bootstrap/values.yaml
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  case "$1" in
    dev | stg | prod)
      echo "==> Ignoring overlay '$1' (no Helm overlays)."
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
fi

if [[ -n "${2:-}" ]]; then
  echo "Unexpected argument: $2" >&2
  usage >&2
  exit 1
fi

echo "==> Day 1: Argo CD"
"$SCRIPT_DIR/argocd/install.sh"

echo ""
echo "Day 1 complete."
echo "  kubectl get pods -n argocd"
echo "  Day 2: ./scripts/gitops/start.sh <profile>  (see gitops/README.md)"
