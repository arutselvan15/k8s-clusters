#!/bin/bash
# Source from argocd/install.sh only.
# Loads committed defaults.env, then sensitive/bootstrap/bootstrap.env if present.

_BOOTSTRAP_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_BOOTSTRAP_ENV_DIR}/../.." && pwd)"
_SENSITIVE_BOOTSTRAP="${_REPO_ROOT}/sensitive/bootstrap"
_SENSITIVE_ENV="${_SENSITIVE_BOOTSTRAP}/bootstrap.env"
_LEGACY_ENV="${_BOOTSTRAP_ENV_DIR}/bootstrap.env"

if [[ -f "${_LEGACY_ENV}" && ! -f "${_SENSITIVE_ENV}" ]]; then
  mkdir -p "${_SENSITIVE_BOOTSTRAP}"
  mv "${_LEGACY_ENV}" "${_SENSITIVE_ENV}"
  echo "==> Moved ${_LEGACY_ENV} -> ${_SENSITIVE_ENV}"
fi

set -a
# shellcheck source=defaults.env
source "${_BOOTSTRAP_ENV_DIR}/defaults.env"
if [[ -f "${_SENSITIVE_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${_SENSITIVE_ENV}"
fi
set +a

unset _BOOTSTRAP_ENV_DIR _REPO_ROOT _SENSITIVE_BOOTSTRAP _SENSITIVE_ENV _LEGACY_ENV
