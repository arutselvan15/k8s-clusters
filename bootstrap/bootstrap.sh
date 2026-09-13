#!/usr/bin/env bash
# Day 1: load env, Helm-install Argo CD, apply secrets YAML.

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/sensitive/bootstrap/bootstrap.env"
VALUES="${ROOT}/bootstrap/argocd/values.yaml"
SECRETS="${ROOT}/sensitive/bootstrap/secrets"
CHART_VERSION="${ARGO_CD_CHART_VERSION:-9.5.21}"

load_env() {
  [[ -f "${ENV_FILE}" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

install_argocd() {
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --create-namespace \
    --version "${CHART_VERSION}" \
    --values "${VALUES}" \
    --wait
}

apply_secrets() {
  local f
  mkdir -p "${SECRETS}"
  for f in "${SECRETS}"/*.yaml; do
    [[ -f "${f}" ]] || continue
    kubectl apply -f "${f}"
  done
}

load_env
install_argocd
apply_secrets
