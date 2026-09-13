#!/usr/bin/env bash
# Source from openstack/up.sh and openstack/down.sh.
# Points Terraform at sensitive/openstack/clouds.yaml. Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing os-env.sh}"

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"

export OS_CLIENT_CONFIG_FILE="${K8S_PLAT_OS_CLOUDS}"

k8s_plat_require_os_credentials() {
  mkdir -p "${K8S_PLAT_SENSITIVE_DIR}/openstack"

  if [[ ! -f "${OS_CLIENT_CONFIG_FILE}" ]]; then
    if [[ -f "${HOME}/.config/openstack/clouds.yaml" ]]; then
      cp "${HOME}/.config/openstack/clouds.yaml" "${OS_CLIENT_CONFIG_FILE}"
      chmod 600 "${OS_CLIENT_CONFIG_FILE}"
      echo "==> Copied ~/.config/openstack/clouds.yaml -> ${OS_CLIENT_CONFIG_FILE} (gitignored)"
    else
      echo "Missing ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "  cp ${K8S_PLAT_SENSITIVE_DIR}/openstack/clouds.yaml.example ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "  chmod 600 ${OS_CLIENT_CONFIG_FILE}" >&2
      return 1
    fi
  fi
  chmod 600 "${OS_CLIENT_CONFIG_FILE}"
}

k8s_plat_os_reject_placeholder() {
  local key="$1"
  local val="$2"
  if [[ "${val}" == "REPLACE_ME" ]]; then
    echo "Set ${key} in ${K8S_PLAT_CLUSTER_CONFIG} (Horizon: Images / Flavors / Networks)." >&2
    return 1
  fi
}

# Writes gitignored JSON for octavia_lbs (list length N).
k8s_plat_os_write_octavia_tfvars() {
  local yaml="${1:?}"
  local outfile="${2:?}"
  python3 - "$yaml" "$outfile" <<'PY'
import json
import sys

path, outfile = sys.argv[1], sys.argv[2]


def parse_scalar(raw):
    text = str(raw).strip()
    if (len(text) >= 2) and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    if " #" in text:
        text = text.split(" #", 1)[0].rstrip()
    return text


def load_simple(path):
    data = {"terraform": {}}
    section = None
    lbs = []
    current = None
    in_lbs = False
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" "))
            stripped = line.strip()
            if ":" not in stripped and not stripped.startswith("- "):
                continue
            if indent == 0:
                if current:
                    lbs.append(current)
                    current = None
                in_lbs = False
                name, rest = stripped.split(":", 1)
                section = name.strip() if rest.strip() == "" else None
                continue
            if section != "terraform":
                continue
            if indent == 2:
                if current:
                    lbs.append(current)
                    current = None
                name, rest = stripped.split(":", 1)
                name, rest = name.strip(), rest.strip()
                if name == "octavia_lbs":
                    in_lbs = True
                    if rest in ("[]", "~", "null"):
                        in_lbs = False
                    continue
                in_lbs = False
                data["terraform"][name] = parse_scalar(rest)
                continue
            if in_lbs and indent == 4 and stripped.startswith("- "):
                if current:
                    lbs.append(current)
                current = {}
                rest = stripped[2:].strip()
                if ":" in rest:
                    key, val = rest.split(":", 1)
                    current[key.strip()] = parse_scalar(val)
                continue
            if in_lbs and current is not None and indent >= 6 and ":" in stripped:
                key, val = stripped.split(":", 1)
                current[key.strip()] = parse_scalar(val)
    if current:
        lbs.append(current)
    if lbs:
        data["terraform"]["octavia_lbs"] = lbs
    elif "octavia_lbs" not in data["terraform"]:
        data["terraform"]["octavia_lbs"] = []
    return data


def load(path):
    try:
        import yaml
    except ImportError:
        yaml = None
    if yaml is not None:
        with open(path, encoding="utf-8") as handle:
            return yaml.safe_load(handle) or {}
    return load_simple(path)


def as_bool(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "yes", "1")


def as_int(value, default):
    if value is None or value == "":
        return default
    return int(value)


def item(name, http_port, https_port):
    return {
        "name": str(name),
        "http_node_port": as_int(http_port, 30080),
        "https_node_port": as_int(https_port, 30443),
    }


doc = load(path)
if not isinstance(doc, dict):
    print("cluster YAML must be a mapping", file=sys.stderr)
    sys.exit(1)
tf = doc.get("terraform") or {}
if not isinstance(tf, dict):
    tf = {}

flavor = tf.get("octavia_lb_flavor") or tf.get("ingress_lb_flavor") or "Octavia_2vCPUx2GB"
raw = tf.get("octavia_lbs")
lbs = []
if isinstance(raw, list) and raw:
    for entry in raw:
        if not isinstance(entry, dict) or not entry.get("name"):
            print("each octavia_lbs entry needs a name", file=sys.stderr)
            sys.exit(1)
        lbs.append(item(entry["name"], entry.get("http_node_port"), entry.get("https_node_port")))
elif as_bool(tf.get("ingress_lb_enabled", False)) or as_bool(tf.get("extra_lb_enabled", False)):
    if as_bool(tf.get("ingress_lb_enabled", False)):
        lbs.append(item("ingress", tf.get("ingress_http_node_port"), tf.get("ingress_https_node_port")))
    if as_bool(tf.get("extra_lb_enabled", False)):
        lbs.append(
            item(
                tf.get("extra_lb_name") or "extra",
                tf.get("extra_http_node_port"),
                tf.get("extra_https_node_port"),
            )
        )

names = [lb["name"] for lb in lbs]
if len(names) != len(set(names)):
    print("octavia_lbs names must be unique", file=sys.stderr)
    sys.exit(1)

payload = {"octavia_lb_flavor": str(flavor), "octavia_lbs": lbs}
with open(outfile, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
print(f"{len(lbs)}\t{' '.join(names)}")
PY
}

k8s_plat_load_os_provider_vars() {
  local yaml="${K8S_PLAT_CLUSTER_CONFIG:?cluster config not resolved}"
  local cloud cluster_name admin_cidr network_name image_name
  local node_flavor worker_nodes ssh_user root_volume_gb availability_zone
  local ssh_port kube_port ssh_key_algorithm image_most_recent volume_delete
  local octavia_tfvars octavia_n octavia_names subnet_name

  cloud="$(k8s_plat_yaml_require "${yaml}" cloud)" || return 1
  export OS_CLOUD="${cloud}"

  cluster_name="${K8S_PLAT_CLUSTER_NAME:?cluster_name not set; pass a cluster id to up.sh}"
  admin_cidr="$(k8s_plat_yaml_require "${yaml}" admin_cidr)" || return 1
  ssh_port="$(k8s_plat_yaml_require "${yaml}" ssh_port)" || return 1
  kube_port="$(k8s_plat_yaml_require "${yaml}" kubernetes_api_port)" || return 1
  network_name="$(k8s_plat_yaml_require "${yaml}" network_name)" || return 1
  image_name="$(k8s_plat_yaml_require "${yaml}" image_name)" || return 1
  node_flavor="$(k8s_plat_yaml_require "${yaml}" node_flavor)" || return 1
  worker_nodes="$(k8s_plat_yaml_require "${yaml}" worker_nodes)" || return 1
  ssh_user="$(k8s_plat_yaml_require "${yaml}" ssh_user)" || return 1
  root_volume_gb="$(k8s_plat_yaml_require "${yaml}" root_volume_gb)" || return 1
  availability_zone="$(k8s_plat_yaml_require "${yaml}" availability_zone)" || return 1
  ssh_key_algorithm="$(k8s_plat_yaml_require "${yaml}" ssh_key_algorithm)" || return 1
  image_most_recent="$(k8s_plat_yaml_require "${yaml}" image_most_recent)" || return 1
  volume_delete="$(k8s_plat_yaml_require "${yaml}" volume_delete_on_termination)" || return 1

  mkdir -p "${K8S_PLAT_CLUSTER_DIR:?cluster dir not set}"
  octavia_tfvars="${K8S_PLAT_CLUSTER_DIR}/octavia.tfvars.json"
  IFS=$'\t' read -r octavia_n octavia_names < <(k8s_plat_os_write_octavia_tfvars "${yaml}" "${octavia_tfvars}") || return 1
  subnet_name="$(k8s_plat_yaml_get "${yaml}" subnet_name 2>/dev/null || true)"
  if [[ "${octavia_n}" != "0" && -z "${subnet_name}" ]]; then
    echo "Set terraform.subnet_name in ${yaml} (this Neutron network has multiple subnets; Octavia needs one)." >&2
    return 1
  fi

  k8s_plat_os_reject_placeholder image_name "${image_name}" || return 1
  k8s_plat_os_reject_placeholder node_flavor "${node_flavor}" || return 1
  k8s_plat_os_reject_placeholder network_name "${network_name}" || return 1

  echo "==> OpenStack from ${OS_CLIENT_CONFIG_FILE} cloud=${cloud}"
  echo "    cluster_name=${cluster_name} network_name=${network_name} admin_cidr=${admin_cidr}"
  echo "    image_name=${image_name} node_flavor=${node_flavor} worker_nodes=${worker_nodes}"
  echo "    nodes ${cluster_name}-cp / ${cluster_name}-wk-N"
  echo "    ssh_user=${ssh_user}"
  echo "    octavia_lbs=${octavia_n} [${octavia_names}] subnet_name=${subnet_name} tfvars=${octavia_tfvars}"
  echo "    cluster config=${yaml}"

  K8S_TF_VAR_ARGS=(
    -var "cloud=${cloud}"
    -var "cluster_name=${cluster_name}"
    -var "ssh_private_key_path=${K8S_PLAT_CLUSTER_SSH_KEY}"
    -var "admin_cidr=${admin_cidr}"
    -var "ssh_port=${ssh_port}"
    -var "kubernetes_api_port=${kube_port}"
    -var "network_name=${network_name}"
    -var "image_name=${image_name}"
    -var "image_most_recent=${image_most_recent}"
    -var "node_flavor=${node_flavor}"
    -var "worker_nodes=${worker_nodes}"
    -var "ssh_user=${ssh_user}"
    -var "ssh_key_algorithm=${ssh_key_algorithm}"
    -var "root_volume_gb=${root_volume_gb}"
    -var "volume_delete_on_termination=${volume_delete}"
    -var "availability_zone=${availability_zone}"
    -var "subnet_name=${subnet_name}"
    -var-file "${octavia_tfvars}"
  )
}
