#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <profile>

Day 2 — apply the App-of-Apps seed (Application core-apps) for a cluster profile.
Requires Day 1 (Argo CD + repo Secrets) and KUBECONFIG pointing at the cluster.

Safe to re-run (kubectl apply).

Profiles: dev, stg, prod (must match gitops/clusters/<profile>/)

Example:
  source scripts/lib/kubeconfig-setup.sh .kube/kind-dev.yaml
  $(basename "$0") dev

See: gitops/README.md
EOF
}

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
  usage
  exit 1
fi

if [[ "${2:-}" != "" ]]; then
  echo "Unexpected argument: $2" >&2
  usage >&2
  exit 1
fi

"$REPO_ROOT/scripts/lib/require-tools.sh" kubectl

CORE_APP="${REPO_ROOT}/gitops/clusters/${PROFILE}/core.application.yaml"
if [[ ! -f "$CORE_APP" ]]; then
  echo "No seed manifest: ${CORE_APP}" >&2
  exit 1
fi

echo "==> Day 2: GitOps seed (core-apps)"
kubectl apply -f "$CORE_APP"
echo ""
echo "GitOps started for '${PROFILE}'. Push gitops/ to Git, then:"
echo "  kubectl get applications -n argocd"
