#!/usr/bin/env bash
# Repo-relative input (config/) and output (clusters/) paths.
# Source after REPO_ROOT is set.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing paths.sh}"

K8S_PLAT_CONFIG_DIR="${REPO_ROOT}/config"
K8S_PLAT_CLUSTERS_DIR="${REPO_ROOT}/clusters"

# --- AWS inputs (auth is shared; cluster knobs are config/aws/clusters/*.yaml) ---
K8S_PLAT_AWS_CREDENTIALS="${K8S_PLAT_CONFIG_DIR}/aws/credentials"
K8S_PLAT_AWS_CLI_CONF="${K8S_PLAT_CONFIG_DIR}/aws/cli.conf"
K8S_PLAT_AWS_INFRA_YAML="${K8S_PLAT_CONFIG_DIR}/aws/clusters/default.yaml"

# --- OpenStack inputs ---
K8S_PLAT_OS_CLOUDS="${K8S_PLAT_CONFIG_DIR}/openstack/clouds.yaml"
K8S_PLAT_OS_INFRA_YAML="${K8S_PLAT_CONFIG_DIR}/openstack/clusters/default.yaml"

# Cluster output paths are bound after k8s_plat_apply_cluster_outputs
# (clusters/<cluster_name>/). Placeholders until a config is selected:
K8S_PLAT_AWS_CLUSTER_DIR="${K8S_PLAT_CLUSTERS_DIR}/aws"
K8S_PLAT_AWS_KUBECONFIG="${K8S_PLAT_AWS_CLUSTER_DIR}/kubeconfig"
K8S_PLAT_AWS_SSH_KEY="${K8S_PLAT_AWS_CLUSTER_DIR}/ssh.pem"
K8S_PLAT_AWS_CLUSTER_ENV="${K8S_PLAT_AWS_CLUSTER_DIR}/cluster.env"
K8S_PLAT_AWS_KNOWN_HOSTS="${K8S_PLAT_AWS_CLUSTER_DIR}/known_hosts"
K8S_PLAT_OS_CLUSTER_DIR="${K8S_PLAT_CLUSTERS_DIR}/openstack"
K8S_PLAT_OS_KUBECONFIG="${K8S_PLAT_OS_CLUSTER_DIR}/kubeconfig"
K8S_PLAT_OS_SSH_KEY="${K8S_PLAT_OS_CLUSTER_DIR}/ssh.pem"
K8S_PLAT_OS_CLUSTER_ENV="${K8S_PLAT_OS_CLUSTER_DIR}/cluster.env"
K8S_PLAT_OS_KNOWN_HOSTS="${K8S_PLAT_OS_CLUSTER_DIR}/known_hosts"

# --- Kind outputs ---
K8S_PLAT_KIND_CLUSTER_DIR="${K8S_PLAT_CLUSTERS_DIR}/kind"
K8S_PLAT_KIND_KUBECONFIG="${K8S_PLAT_KIND_CLUSTER_DIR}/kubeconfig"

k8s_plat_ini_get() {
  local file="$1"
  local key="$2"
  local section="${3:-default}"
  python3 - "$file" "$key" "$section" <<'PY'
import configparser, sys

path, key, section = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = configparser.RawConfigParser()
if not cfg.read(path):
    sys.exit(1)
if section == "default":
    use = "default" if cfg.has_section("default") else "DEFAULT"
else:
    use = section
    if not cfg.has_section(use) and cfg.has_section(f"profile {use}"):
        use = f"profile {use}"
if not cfg.has_section(use) and use != "DEFAULT":
    sys.exit(1)
if not cfg.has_option(use, key):
    sys.exit(1)
value = cfg.get(use, key).strip().strip('"').strip("'")
if not value:
    sys.exit(1)
print(value)
PY
}

# Read a scalar from lab YAML. Key is dotted (terraform.vpc_cidr) or a short
# name (vpc_cidr), which also searches terraform.* and kubeadm.*.
k8s_plat_yaml_get() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import sys

path, key = sys.argv[1], sys.argv[2]


def to_str(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def parse_scalar(raw):
    text = raw.strip()
    if not text or text in ("~", "null", "Null", "NULL"):
        return ""
    if (len(text) >= 2) and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    if " #" in text:
        text = text.split(" #", 1)[0].rstrip()
    return text


def load_simple(path):
    data = {}
    section = None
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" "))
            if indent not in (0, 2):
                sys.exit(1)
            stripped = line.strip()
            if ":" not in stripped:
                sys.exit(1)
            name, rest = stripped.split(":", 1)
            name = name.strip()
            rest = rest.strip()
            if indent == 0:
                if rest == "":
                    section = name
                    data[section] = {}
                else:
                    section = None
                    data[name] = parse_scalar(rest)
            else:
                if section is None or not isinstance(data.get(section), dict):
                    sys.exit(1)
                data[section][name] = parse_scalar(rest)
    return data


def load(path):
    try:
        import yaml  # type: ignore
    except ImportError:
        yaml = None
    if yaml is not None:
        with open(path, encoding="utf-8") as handle:
            loaded = yaml.safe_load(handle)
        return loaded or {}
    return load_simple(path)


def walk(data, dotted):
    cur = data
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    if isinstance(cur, dict):
        return None
    return cur


try:
    doc = load(path)
except OSError:
    sys.exit(1)
if not isinstance(doc, dict):
    sys.exit(1)

candidates = [key]
if "." not in key:
    candidates.extend([f"terraform.{key}", f"kubeadm.{key}", f"nodes.{key}"])

found = False
result = ""
for cand in candidates:
    got = walk(doc, cand)
    if got is not None:
        found = True
        result = to_str(got)
        break
if not found:
    sys.exit(1)
print(result, end="")
PY
}
