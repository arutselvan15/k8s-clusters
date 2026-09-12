#!/usr/bin/env bash
# Shared by scripts/infra/kind/up.sh and down.sh. Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing scripts/infra/kind/lib.sh}"

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"

K8S_PLAT_KIND_ENV_DIR="${REPO_ROOT}/infra/terraform/environments/kind"
K8S_TF_VAR_ARGS=()

k8s_plat_kind_bind() {
  local spec="${1:-}"
  k8s_plat_resolve_cluster_config kind "${spec}" || return 1
  k8s_plat_apply_cluster_outputs
}

k8s_plat_load_kind_vars() {
  local cluster_name k8s_ver cp_nodes workers http_port https_port
  local yaml="${K8S_PLAT_CLUSTER_CONFIG:?cluster config not resolved}"

  cluster_name="${K8S_PLAT_CLUSTER_NAME:?cluster_name not set}"
  k8s_ver="$(k8s_plat_yaml_require "${yaml}" kubernetes_version)" || return 1
  cp_nodes="$(k8s_plat_yaml_require "${yaml}" control_plane_nodes)" || return 1
  workers="$(k8s_plat_yaml_require "${yaml}" worker_nodes)" || return 1
  http_port="$(k8s_plat_yaml_require "${yaml}" http_host_port)" || return 1
  https_port="$(k8s_plat_yaml_require "${yaml}" https_host_port)" || return 1

  echo "==> Kind from ${yaml}"
  echo "    cluster_name=${cluster_name} kubernetes_version=${k8s_ver}"
  echo "    control_plane_nodes=${cp_nodes} worker_nodes=${workers}"
  echo "    host ports ${http_port}->80 ${https_port}->443"
  K8S_TF_VAR_ARGS=(
    -var "cluster_name=${cluster_name}"
    -var "kubernetes_version=${k8s_ver}"
    -var "control_plane_nodes=${cp_nodes}"
    -var "worker_nodes=${workers}"
    -var "kubeconfig_path=${K8S_PLAT_CLUSTER_KUBECONFIG}"
    -var "http_host_port=${http_port}"
    -var "https_host_port=${https_port}"
  )
}

k8s_plat_kind_terraform_init() {
  k8s_plat_terraform_init "${K8S_PLAT_KIND_ENV_DIR}"
}

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
