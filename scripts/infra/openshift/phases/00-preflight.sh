#!/usr/bin/env bash
# Preflight: laptop tools, credentials, pull secret, cloud objects and quota.
#
# Runs on: laptop. Creates nothing.
#
# Why: an OpenShift install fails 20-40 minutes in if a flavor is missing or
# the project is out of cores. Every check here is a read-only API call, so
# it is cheap to find those problems now.
#
# Checks:
#   - terraform, openstack, helm, yq, jq, ssh on PATH
#   - clouds.yaml has the cloud named in the config, and it authenticates
#   - sensitive/openshift/pull-secret.json (console.redhat.com) is valid
#   - flavors, jump host image and volume type exist
#   - mode create: the external network is external in this project
#     mode existing: the provider network and subnet exist, and both VIPs are
#     addresses inside that subnet
#   - quota for jump host + bootstrap + masters + workers: instances, cores,
#     RAM, volumes, GB, security groups, plus floating IPs, networks and
#     routers when mode is create
#
# Learn: openstack quota show --usage; openstack flavor show <flavor>

"${REPO_ROOT}/scripts/lib/require-tools.sh" terraform openstack helm yq jq ssh python3 curl

ocp_step "clouds.yaml: ${OS_CLIENT_CONFIG_FILE} cloud=${OCP_CLOUD}"
k8s_plat_require_os_credentials
if [[ "$(yq ".clouds | has(\"${OCP_CLOUD}\")" "${OS_CLIENT_CONFIG_FILE}")" != "true" ]]; then
  ocp_die "No '${OCP_CLOUD}' under clouds: in ${OS_CLIENT_CONFIG_FILE}.
  Horizon -> select project -> Identity -> Application Credentials -> Create,
  then add it as clouds.${OCP_CLOUD} (same shape as the other entries)."
fi

ocp_step "pull secret: ${OCP_PULL_SECRET}"
if [[ ! -f "${OCP_PULL_SECRET}" ]]; then
  ocp_die "Missing pull secret. Download it from
  https://console.redhat.com/openshift/install/pull-secret and save it as
  ${OCP_PULL_SECRET} (gitignored)."
fi
chmod 600 "${OCP_PULL_SECRET}"
for registry in cloud.openshift.com quay.io registry.redhat.io registry.connect.redhat.com; do
  if ! jq -e --arg r "${registry}" '.auths[$r].auth | length > 0' "${OCP_PULL_SECRET}" >/dev/null 2>&1; then
    ocp_die "pull secret has no auth for ${registry} (wrong file or truncated JSON)"
  fi
done
echo "    auths: $(jq -r '.auths | keys | join(", ")' "${OCP_PULL_SECRET}")"

ocp_step "authenticate (OpenStack calls here are slow; ~10-30s each)"
project_id="$(openstack token issue -f value -c project_id)" || ocp_die "Authentication failed for cloud ${OCP_CLOUD}"
echo "    project_id=${project_id}"

machine_cidr=""
if [[ "${OCP_NETWORK_MODE}" == "existing" ]]; then
  ocp_step "provider network ${OCP_EXISTING_NETWORK} / subnet ${OCP_EXISTING_SUBNET}"
  openstack network show "${OCP_EXISTING_NETWORK}" -f value -c id >/dev/null ||
    ocp_die "network ${OCP_EXISTING_NETWORK} not visible in this project"
  machine_cidr="$(openstack subnet show "${OCP_EXISTING_SUBNET}" -f value -c cidr)" ||
    ocp_die "subnet ${OCP_EXISTING_SUBNET} not visible in this project"
  echo "    machine network ${machine_cidr} (install-config machineNetwork)"

  # The VIPs are plain addresses on a subnet this project does not own, and
  # ports belonging to other projects are invisible here, so this proves only
  # that the addresses are inside the subnet and unused by us. A collision
  # with another tenant surfaces in phase 60 as a port create failure.
  ocp_step "VIPs ${OCP_API_VIP} (API) and ${OCP_INGRESS_VIP} (ingress)"
  python3 - "${machine_cidr}" "${OCP_API_VIP}" "${OCP_INGRESS_VIP}" <<'PY' || ocp_die "VIPs are not usable on this subnet"
import ipaddress
import sys

net = ipaddress.ip_network(sys.argv[1])
api, ingress = (ipaddress.ip_address(a) for a in sys.argv[2:4])
bad = []
for name, vip in (("api_vip", api), ("ingress_vip", ingress)):
    if vip not in net:
        bad.append(f"{name} {vip} is outside the subnet {net}")
    elif vip in (net.network_address, net.broadcast_address):
        bad.append(f"{name} {vip} is the network or broadcast address of {net}")
if api == ingress:
    bad.append("api_vip and ingress_vip must differ")
if bad:
    print("\n  ".join(["Bad VIPs:"] + bad), file=sys.stderr)
    sys.exit(1)
PY
  for vip in "${OCP_API_VIP}" "${OCP_INGRESS_VIP}"; do
    if [[ -n "$(openstack port list --fixed-ip "ip-address=${vip}" -f value -c ID)" ]]; then
      ocp_die "a port in this project already holds ${vip}; pick another VIP"
    fi
  done
  echo "    inside ${machine_cidr}, and no port of this project holds them"
  echo "    (other projects' ports are invisible; the subnet's DHCP pool can"
  echo "     still hand a VIP out before phase 60 claims it)"
else
  ocp_step "external network ${OCP_EXTERNAL_NETWORK}"
  [[ "$(openstack network show "${OCP_EXTERNAL_NETWORK}" -f value -c router:external)" == "True" ]] ||
    ocp_die "${OCP_EXTERNAL_NETWORK} is not an external network in this project"
  machine_cidr="${OCP_NET_CIDR}"
fi

ocp_step "jump host image ${OCP_JUMP_IMAGE}"
openstack image show "${OCP_JUMP_IMAGE}" -f value -c id >/dev/null ||
  ocp_die "image ${OCP_JUMP_IMAGE} not visible"

if [[ -n "${OCP_CLUSTER_OS_IMAGE}" ]]; then
  ocp_step "RHCOS image ${OCP_CLUSTER_OS_IMAGE}"
  openstack image show "${OCP_CLUSTER_OS_IMAGE}" -f value -c id >/dev/null ||
    ocp_die "image ${OCP_CLUSTER_OS_IMAGE} not visible"
fi

ocp_step "volume type ${OCP_VOLUME_TYPE}"
openstack volume type show "${OCP_VOLUME_TYPE}" -f value -c id >/dev/null ||
  ocp_die "volume type ${OCP_VOLUME_TYPE} not visible"

flavor_json() {
  openstack flavor show "$1" -f json || ocp_die "flavor $1 not found"
}

# flavor_min <role> <flavor json> <min vCPU> <min RAM MB>
flavor_min() {
  local cpu ram disk
  cpu="$(jq -r .vcpus <<<"$2")"
  ram="$(jq -r .ram <<<"$2")"
  disk="$(jq -r .disk <<<"$2")"
  echo "    $1: $(jq -r .name <<<"$2") ${cpu} vCPU ${ram} MB ${disk} GB disk"
  if (( cpu < $3 || ram < $4 )); then
    ocp_die "$1 flavor is below the OpenShift minimum ($3 vCPU / $4 MB)"
  fi
  # root_volume_gb 0 means this disk is the node's only storage.
  if (( OCP_ROOT_VOLUME_GB == 0 )); then
    if (( disk < 25 )); then
      ocp_die "openshift.root_volume_gb is 0, so $1 boots from the flavor disk, and ${disk} GB is below the installer's 25 GB minimum"
    fi
    if (( disk < 100 )); then
      echo "    WARNING: $1 boots from a ${disk} GB local disk. OpenShift asks for 100 GB per node;"
      echo "             below that, image garbage collection runs often and etcd has little headroom."
    fi
  fi
}

ocp_step "flavors"
jump_flavor="$(flavor_json "${OCP_JUMP_FLAVOR}")"
cp_flavor="$(flavor_json "${OCP_CP_FLAVOR}")"
compute_flavor="$(flavor_json "${OCP_COMPUTE_FLAVOR}")"
echo "    jump host: $(jq -r .name <<<"${jump_flavor}")"
flavor_min control_plane "${cp_flavor}" 4 16384
flavor_min compute "${compute_flavor}" 2 8192

ocp_step "quota (need = jump + bootstrap + ${OCP_CP_REPLICAS} masters + ${OCP_COMPUTE_REPLICAS} workers)"
quota="$(openstack quota show --usage -f json)"
python3 - "${quota}" "${jump_flavor}" "${cp_flavor}" "${compute_flavor}" \
  "${OCP_CP_REPLICAS}" "${OCP_COMPUTE_REPLICAS}" "${OCP_ROOT_VOLUME_GB}" "${OCP_JUMP_ROOT_GB}" \
  "${OCP_NETWORK_MODE}" <<'PY'
import json
import sys

quota = {q["Resource"]: q for q in json.loads(sys.argv[1])}
jump, cp, wk = (json.loads(a) for a in sys.argv[2:5])
n_cp, n_wk, root_gb, jump_gb = (int(a) for a in sys.argv[5:9])
network_mode = sys.argv[9]
n_cp_like = n_cp + 1  # bootstrap uses the control-plane flavor
registry_gb = 100     # no Swift here, so the image registry gets a Cinder PVC

# A root_volume_gb or jumphost root_volume_gb of 0 boots that machine from its
# flavor's local disk, which costs no volume and no gigabyte of quota.
node_volumes = (n_cp_like + n_wk) if root_gb else 0
jump_volumes = 1 if jump_gb else 0

need = {
    "instances": 1 + n_cp_like + n_wk,
    "cores": jump["vcpus"] + n_cp_like * cp["vcpus"] + n_wk * wk["vcpus"],
    "ram": jump["ram"] + n_cp_like * cp["ram"] + n_wk * wk["ram"],
    "volumes": jump_volumes + node_volumes + 1,
    "gigabytes": jump_gb + node_volumes * root_gb + registry_gb,
    "security_groups": 3,
}
# mode=existing creates no network, router or floating IP: the jump host and
# the VIPs sit on a provider network that already routes.
if network_mode == "create":
    need.update({
        "floating_ips": 3,
        "networks": 1,
        "subnets": 1,
        "routers": 1,
    })

short = []
print(f"    {'resource':<16}{'limit':>10}{'in use':>10}{'free':>10}{'need':>10}")
for name, want in need.items():
    q = quota.get(name)
    if q is None:
        print(f"    {name:<16}{'?':>10}{'?':>10}{'?':>10}{want:>10}  (not reported)")
        continue
    limit, used = q.get("Limit"), q.get("In Use") or 0
    if limit is None or int(limit) < 0:
        free = "unlimited"
    else:
        free = int(limit) - int(used)
        if free < want:
            short.append(f"{name}: need {want}, free {free}")
    print(f"    {name:<16}{str(limit):>10}{str(used):>10}{str(free):>10}{want:>10}")

rules = quota.get("security_group_rules")
if rules:
    print(f"    security_group_rules: limit {rules.get('Limit')}, in use {rules.get('In Use')}"
          " (installer adds its own; it re-checks quota before creating VMs)")
if short:
    print("\nNot enough quota:\n  " + "\n  ".join(short), file=sys.stderr)
    sys.exit(1)
PY

echo ""
if [[ "${OCP_NETWORK_MODE}" == "existing" ]]; then
  echo "Preflight passed. Phase 10 creates only the jump host, on ${OCP_EXISTING_SUBNET}."
else
  echo "Preflight passed. Phase 10 creates the network, router, jump host and floating IPs."
fi
