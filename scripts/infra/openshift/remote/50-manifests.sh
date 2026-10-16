#!/usr/bin/env bash
# Phase 50 on the jump host. Env: OCP_WORK, OCP_INSTALL
# Re-runnable: starts from install-config.yaml.bak every time, until a
# cluster has been created from this dir.

set -euo pipefail

if [[ -f "${OCP_INSTALL}/metadata.json" ]]; then
  echo "A cluster was already created from ${OCP_INSTALL}; refusing to regenerate manifests." >&2
  exit 1
fi
if [[ ! -f "${OCP_WORK}/install-config.yaml.bak" ]]; then
  echo "Missing ${OCP_WORK}/install-config.yaml.bak - run phase 40 first." >&2
  exit 1
fi

rm -rf "${OCP_INSTALL}"
mkdir -p "${OCP_INSTALL}"
cp "${OCP_WORK}/install-config.yaml.bak" "${OCP_INSTALL}/install-config.yaml"

openshift-install create manifests --dir "${OCP_INSTALL}" 2>&1 | sed 's/^/    /'
echo "    install-config.yaml consumed; state in ${OCP_INSTALL}/.openshift_install_state.json"
