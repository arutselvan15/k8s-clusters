#!/usr/bin/env bash
# Phase 30 on the jump host. Env: OCP_RELEASE, OCP_WORK

set -euo pipefail

mirror="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE}"
dl="${OCP_WORK}/downloads/${OCP_RELEASE}"
mkdir -p "${dl}"
cd "${dl}"

echo "==> ${mirror}"
curl -fsSL -o sha256sum.txt "${mirror}/sha256sum.txt"
for f in "openshift-install-linux-${OCP_RELEASE}.tar.gz" "openshift-client-linux-${OCP_RELEASE}.tar.gz"; do
  if [[ ! -f "${f}" ]]; then
    echo "    downloading ${f}"
    curl -fsSL -o "${f}.part" "${mirror}/${f}"
    mv "${f}.part" "${f}"
  fi
done

echo "==> sha256 verify"
grep -E " (openshift-install|openshift-client)-linux-${OCP_RELEASE}\.tar\.gz$" sha256sum.txt | sha256sum -c - | sed 's/^/    /'

echo "==> install to /usr/local/bin"
tar -xzf "openshift-install-linux-${OCP_RELEASE}.tar.gz" openshift-install
tar -xzf "openshift-client-linux-${OCP_RELEASE}.tar.gz" oc kubectl
sudo install -m 0755 openshift-install oc kubectl /usr/local/bin/
rm -f openshift-install oc kubectl

echo "==> versions"
openshift-install version | sed 's/^/    /'
oc version --client | sed 's/^/    /'

echo "==> RHCOS image the installer will upload to Glance (unless cluster_os_image is set)"
openshift-install coreos print-stream-json |
  jq -r '.architectures.x86_64 | "    RHCOS \(.artifacts.openstack.release)\n    \(.artifacts.openstack.formats["qcow2.gz"].disk.location)"'
