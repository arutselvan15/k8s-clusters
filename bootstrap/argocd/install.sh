#!/bin/bash

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${BOOTSTRAP_DIR}/.." && pwd)"
REPOS_DIR="${SCRIPT_DIR}/repos"
VALUES_FILE="${SCRIPT_DIR}/values.yaml"
VALUES_SENSITIVE="${REPO_ROOT}/sensitive/bootstrap/values.yaml"

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
  echo "Setting Argo CD admin password from sensitive/bootstrap/bootstrap.env (user admin) ..."
  kubectl patch secret argocd-secret -n argocd --type merge \
    --patch "{\"stringData\":{\"admin.password\":\"${hash}\",\"admin.passwordMtime\":\"${mtime}\"}}"
}

install_argocd() {
  echo "Adding Argo CD Helm repo ..."
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update

  echo "Creating namespace argocd ..."
  kubectl create namespace argocd \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Installing or upgrading Argo CD (chart ${ARGO_CD_CHART_VERSION}) ..."
  if [[ -f "${VALUES_SENSITIVE}" ]]; then
    echo "    extra values ${VALUES_SENSITIVE}"
    helm upgrade --install argocd argo/argo-cd \
      --namespace argocd \
      --version "${ARGO_CD_CHART_VERSION}" \
      --values "${VALUES_FILE}" \
      --values "${VALUES_SENSITIVE}" \
      --wait
  else
    helm upgrade --install argocd argo/argo-cd \
      --namespace argocd \
      --version "${ARGO_CD_CHART_VERSION}" \
      --values "${VALUES_FILE}" \
      --wait
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0")

Installs or upgrades Argo CD with Helm (pinned chart version). Safe to re-run.

Helm values: ${VALUES_FILE}
Optional extra: sensitive/bootstrap/values.yaml
Secrets: sensitive/bootstrap/bootstrap.env

Chart: argo/argo-cd ${ARGO_CD_CHART_VERSION}

After Helm: repo-creds then repos/ (see repos/README.md).
GitOps seed: ./scripts/gitops/start.sh <profile> — not part of bootstrap.

Optional: ARGOCD_ADMIN_PASSWORD in sensitive/bootstrap/bootstrap.env
EOF
}

load_bootstrap_env

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  case "$1" in
    dev | stg | prod)
      echo "==> Ignoring overlay '$1' (Helm uses argocd/values.yaml)."
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

install_argocd
set_argocd_admin_password_from_env
apply_argocd_repo_creds
apply_argocd_repos

echo "Argo CD ready (chart: ${ARGO_CD_CHART_VERSION})."
