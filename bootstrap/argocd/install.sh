#!/bin/bash

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOS_DIR="${SCRIPT_DIR}/repos"
VALUES_BASE="${SCRIPT_DIR}/values/base.yaml"
OVERLAYS_DIR="${SCRIPT_DIR}/values/overlays"

load_bootstrap_env() {
  # shellcheck source=../env/load.sh
  source "${BOOTSTRAP_DIR}/env/load.sh"
}

apply_k8s_from_template() {
  local template=$1
  envsubst < "$template" | kubectl apply -f -
}

apply_manifest() {
  local manifest=$1
  echo "Applying $(basename "$manifest") ..."
  if grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$manifest"; then
    apply_k8s_from_template "$manifest"
  else
    kubectl apply -f "$manifest"
  fi
}

apply_argocd_repo_creds() {
  local f
  shopt -s nullglob
  for f in "${REPOS_DIR}"/repo-creds.*.yaml; do
    apply_manifest "$f"
  done
  shopt -u nullglob
}

apply_argocd_repos() {
  local f
  shopt -s nullglob
  for f in "${REPOS_DIR}"/repo.*.yaml; do
    apply_manifest "$f"
  done
  shopt -u nullglob
}

argocd_admin_bcrypt_hash() {
  local password=$1
  if ! command -v htpasswd >/dev/null 2>&1; then
    echo "htpasswd required to set ARGOCD_ADMIN_PASSWORD (install httpd/openssl tooling)" >&2
    exit 1
  fi
  htpasswd -nbBC 10 "" "$password" | cut -d: -f2 | sed 's/^\$2y\$/\$2a\$/'
}

set_argocd_admin_password_from_env() {
  local hash mtime

  if [[ -z "${ARGOCD_ADMIN_PASSWORD:-}" ]]; then
    return 0
  fi

  if ! kubectl get secret argocd-secret -n argocd >/dev/null 2>&1; then
    echo "argocd-secret not found; skip ARGOCD_ADMIN_PASSWORD patch" >&2
    return 0
  fi

  hash="$(argocd_admin_bcrypt_hash "$ARGOCD_ADMIN_PASSWORD")"
  mtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Setting Argo CD admin password from bootstrap.env (user admin) ..."
  kubectl patch secret argocd-secret -n argocd --type merge \
    --patch "{\"stringData\":{\"admin.password\":\"${hash}\",\"admin.passwordMtime\":\"${mtime}\"}}"
}

install_argocd() {
  local overlay=$1
  local overlay_file="${OVERLAYS_DIR}/${overlay}.yaml"

  echo "Adding Argo CD Helm repo ..."
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update

  echo "Creating namespace argocd ..."
  kubectl create namespace argocd \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Installing or upgrading Argo CD (chart ${ARGO_CD_CHART_VERSION}, overlay ${overlay}) ..."
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version "${ARGO_CD_CHART_VERSION}" \
    --values "$VALUES_BASE" \
    --values "$overlay_file" \
    --wait
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [overlay]

Installs or upgrades Argo CD with Helm (pinned chart version). Safe to re-run.

Overlays: dev, stg, prod (values/overlays/). Default: \$ARGOCD_OVERLAY or dev.

Chart: argo/argo-cd ${ARGO_CD_CHART_VERSION}

After Helm: repo-creds (from bootstrap/env) then repos/ (see repos/README.md).
GitOps (core-apps seed): ./scripts/gitops/start.sh <profile> — not part of bootstrap.

Environment: bootstrap/env/defaults.env + optional bootstrap/env/bootstrap.env
Optional: ARGOCD_ADMIN_PASSWORD in bootstrap.env (patched after Helm; omitted if unset)

Example:
  $(basename "$0") dev
EOF
}

load_bootstrap_env

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

OVERLAY="${1:-${ARGOCD_OVERLAY:-dev}}"

if [[ -n "${2:-}" ]]; then
  echo "Unexpected argument: $2" >&2
  usage >&2
  exit 1
fi

OVERLAY_FILE="${OVERLAYS_DIR}/${OVERLAY}.yaml"
if [[ ! -f "$OVERLAY_FILE" ]]; then
  echo "Unknown overlay '$OVERLAY' (expected ${OVERLAY_FILE})" >&2
  exit 1
fi

install_argocd "$OVERLAY"
set_argocd_admin_password_from_env
apply_argocd_repo_creds
apply_argocd_repos

echo "Argo CD ready (overlay: ${OVERLAY}, chart: ${ARGO_CD_CHART_VERSION})."
