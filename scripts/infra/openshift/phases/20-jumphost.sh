#!/usr/bin/env bash
# Jump host: packages, OpenStack credentials, cluster names, egress checks.
#
# Runs on: jump host (remote/20-jumphost.sh streamed over SSH).
#
# Why: openshift-install runs here, not on the laptop. It needs clouds.yaml to
# call OpenStack, it needs api.<cluster>.<domain> to resolve while it waits
# for the API, and the nodes behind this router need to pull images from
# quay.io and registry.redhat.io. Finding out now that egress is blocked is
# much cheaper than finding out from a bootstrap node that never pulls.
#
# Does:
#   - apt: jq, curl, unzip, dnsutils, tmux, python3-openstackclient
#   - ~/.config/openstack/clouds.yaml with ONLY the '<cloud>' entry (0600)
#   - /etc/hosts: api / api-int -> API VIP, console/oauth -> ingress VIP
#   - curl quay.io, registry.redhat.io, mirror.openshift.com, auth_url
#
# There is no DNS zone for base_domain, so /etc/hosts stands in for it here.
# Inside the cluster, the OpenStack platform runs CoreDNS + keepalived static
# pods that answer api-int and *.apps themselves.
#
# Learn: ssh in and run `openstack server list` - that is the installer's view.

"${REPO_ROOT}/scripts/lib/require-tools.sh" ssh yq
ocp_load_outputs
ocp_wait_ssh

ocp_step "clouds.yaml (only '${OCP_CLOUD}') -> jump host ~/.config/openstack/clouds.yaml"
filtered="$(mktemp)"
trap 'rm -f "${filtered}"' EXIT
yq ".clouds |= pick([\"${OCP_CLOUD}\"])" "${OS_CLIENT_CONFIG_FILE}" >"${filtered}"
ocp_put "${filtered}" "/home/${OCP_SSH_USER}/.config/openstack/clouds.yaml"

hosts="${OCP_API_VIP} ${OCP_API_HOST} ${OCP_API_INT_HOST}
${OCP_INGRESS_VIP} console-openshift-console.${OCP_APPS_DOMAIN} oauth-openshift.${OCP_APPS_DOMAIN} downloads-openshift-console.${OCP_APPS_DOMAIN} canary-openshift-ingress-canary.${OCP_APPS_DOMAIN}"

ocp_remote 20-jumphost.sh \
  "OCP_CNI=${OCP_CNI}" \
  "OCP_HOSTS=${hosts}" \
  "OCP_HTTPS_PROXY=${OCP_HTTPS_PROXY}"
