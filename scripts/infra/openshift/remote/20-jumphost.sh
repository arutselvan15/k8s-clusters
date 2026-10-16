#!/usr/bin/env bash
# Phase 20 on the jump host. Streamed over SSH stdin; not copied.
# Env: OCP_CLOUD, OCP_CNI, OCP_HOSTS (lines "ip name..."), OCP_HTTPS_PROXY, OCP_WORK

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

if command -v cloud-init >/dev/null 2>&1; then
  echo "==> waiting for cloud-init"
  sudo cloud-init status --wait >/dev/null || true
fi

echo "==> apt packages"
n=0
until sudo apt-get update -qq; do
  n=$((n + 1))
  [[ "${n}" -lt 30 ]] || { echo "apt-get update failed" >&2; exit 1; }
  sleep 5
done
sudo apt-get install -y -qq jq curl unzip tar dnsutils tmux python3-openstackclient >/dev/null
echo "    $(jq --version), $(openstack --version 2>&1)"

mkdir -p "${OCP_WORK}"
chmod 700 "${HOME}/.config/openstack"

echo "==> /etc/hosts block for ${OCP_CLUSTER_NAME}"
begin="# BEGIN openshift ${OCP_CLUSTER_NAME}"
end="# END openshift ${OCP_CLUSTER_NAME}"
sudo sed -i "/^${begin}\$/,/^${end}\$/d" /etc/hosts
printf '%s\n%s\n%s\n' "${begin}" "${OCP_HOSTS}" "${end}" | sudo tee -a /etc/hosts >/dev/null
sed -n "/^${begin}\$/,/^${end}\$/p" /etc/hosts | sed 's/^/    /'

echo "==> OpenStack API as the installer will see it (cloud ${OCP_CLOUD})"
export OS_CLOUD="${OCP_CLOUD}"
openstack token issue -f value -c project_id -c expires | sed 's/^/    /'

echo "==> egress from this subnet (nodes use the same router)"
proxy_args=()
if [[ -n "${OCP_HTTPS_PROXY}" ]]; then
  proxy_args=(--proxy "${OCP_HTTPS_PROXY}")
  echo "    via proxy ${OCP_HTTPS_PROXY}"
fi
failed=0
urls=(
  https://quay.io/v2/ \
  https://registry.redhat.io/v2/ \
  https://mirror.openshift.com/pub/openshift-v4/clients/ocp/ \
  https://rhcos.mirror.openshift.com/
)
if [[ "${OCP_CNI}" == "Cilium" ]]; then
  urls+=(https://quay.io/v2/cilium/cilium/tags/list)
fi
for url in "${urls[@]}"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${proxy_args[@]}" "${url}" || true)"
  # 401 is a healthy answer from a registry that wants a token.
  case "${code}" in
    2?? | 3?? | 401 | 403) echo "    ok   ${code} ${url}" ;;
    *)
      echo "    FAIL ${code:-000} ${url}"
      failed=1
      ;;
  esac
done
if [[ "${failed}" -ne 0 ]]; then
  echo "Egress is blocked. Set openshift.proxy.http/https in the cluster config and re-run phase 20." >&2
  exit 1
fi
