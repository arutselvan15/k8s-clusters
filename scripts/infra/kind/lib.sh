#!/usr/bin/env bash
# Shared by scripts/infra/kind/up.sh and down.sh. Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing scripts/infra/kind/lib.sh}"

K8S_PLAT_KIND_ENV_DIR="${REPO_ROOT}/infra/terraform/environments/kind"

k8s_plat_docker_ok() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

k8s_plat_prepare_kind_runtime() {
  if k8s_plat_docker_ok; then
    unset KIND_EXPERIMENTAL_PROVIDER || true
    echo "==> Container runtime: Docker"
    return
  fi

  if ! command -v podman >/dev/null 2>&1; then
    echo "Kind needs Docker or Podman. Neither is usable." >&2
    return 1
  fi

  export KIND_EXPERIMENTAL_PROVIDER=podman
  echo "==> Container runtime: Podman (KIND_EXPERIMENTAL_PROVIDER=podman)"

  if podman info >/dev/null 2>&1; then
    return
  fi

  if podman machine inspect >/dev/null 2>&1; then
    echo "==> Starting Podman machine"
    podman machine start
  fi

  if ! podman info >/dev/null 2>&1; then
    echo "Podman is not reachable. Open Podman Desktop or run: podman machine start" >&2
    return 1
  fi
}
