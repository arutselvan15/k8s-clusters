#!/usr/bin/env bash
# Cluster YAML: clusters/<platform>/<id>/config.yaml (committed).
# Secrets + Terraform outputs: sensitive/ (gitignored, S3).

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing paths.sh}"

# Re-exec the calling CLI if this file was sourced from `sh script` (macOS posix bash).
# shellcheck source=scripts/lib/ensure-bash.sh
. "${REPO_ROOT}/scripts/lib/ensure-bash.sh"

K8S_PLAT_CLUSTER_INPUT_DIR="${REPO_ROOT}/clusters"
K8S_PLAT_SENSITIVE_DIR="${REPO_ROOT}/sensitive"
K8S_PLAT_BACKUP_YAML="${K8S_PLAT_CLUSTER_INPUT_DIR}/backup.yaml"

# --- AWS / OpenStack secrets (not cluster-specific) ---
K8S_PLAT_AWS_CREDENTIALS="${K8S_PLAT_SENSITIVE_DIR}/aws/credentials"
K8S_PLAT_AWS_CLI_CONF="${K8S_PLAT_SENSITIVE_DIR}/aws/cli.conf"
K8S_PLAT_OS_CLOUDS="${K8S_PLAT_SENSITIVE_DIR}/openstack/clouds.yaml"

# --- Kind platform dir (per-cluster outputs: sensitive/kind/<cluster_name>/) ---
K8S_PLAT_KIND_DIR="${K8S_PLAT_SENSITIVE_DIR}/kind"

# Move leftover secrets/outputs into sensitive/. Does not move committed cluster YAML.
k8s_plat_migrate_to_sensitive() {
  local src dest name parent
  mkdir -p \
    "${K8S_PLAT_SENSITIVE_DIR}/aws" \
    "${K8S_PLAT_SENSITIVE_DIR}/openstack" \
    "${K8S_PLAT_SENSITIVE_DIR}/bootstrap"

  for src in \
    "${REPO_ROOT}/config/aws/credentials:${K8S_PLAT_AWS_CREDENTIALS}" \
    "${REPO_ROOT}/config/aws/cli.conf:${K8S_PLAT_AWS_CLI_CONF}" \
    "${REPO_ROOT}/config/openstack/clouds.yaml:${K8S_PLAT_OS_CLOUDS}" \
    "${REPO_ROOT}/bootstrap/env/bootstrap.env:${K8S_PLAT_SENSITIVE_DIR}/bootstrap/bootstrap.env"; do
    dest="${src#*:}"
    src="${src%%:*}"
    if [[ -f "${src}" && ! -f "${dest}" ]]; then
      mkdir -p "$(dirname "${dest}")"
      mv "${src}" "${dest}"
      echo "==> Moved ${src} -> ${dest}"
    fi
  done

  for parent in "${REPO_ROOT}/clusters" "${REPO_ROOT}/sensitive/clusters"; do
    [[ -d "${parent}" ]] || continue
    for src in "${parent}"/*; do
      [[ -d "${src}" ]] || continue
      name="$(basename "${src}")"
      case "${name}" in
        aws | openstack) continue ;;
      esac
      dest="${K8S_PLAT_SENSITIVE_DIR}/${name}"
      if [[ -e "${dest}" ]]; then
        continue
      fi
      if [[ -f "${src}/terraform.tfstate" || -f "${src}/ssh.pem" || -f "${src}/kubeconfig" ]]; then
        mv "${src}" "${dest}"
        echo "==> Moved ${src} -> ${dest}"
      fi
    done
  done

  # Flattened leftovers: sensitive/<cluster_name> -> sensitive/<env>/<cluster_name>
  if [[ -d "${K8S_PLAT_SENSITIVE_DIR}" ]]; then
    for src in "${K8S_PLAT_SENSITIVE_DIR}"/*; do
      [[ -d "${src}" ]] || continue
      name="$(basename "${src}")"
      case "${name}" in
        aws | openstack | kind) continue ;;
      esac
      dest=""
      if [[ -d "${K8S_PLAT_CLUSTER_INPUT_DIR}/aws/${name}" ]]; then
        dest="${K8S_PLAT_SENSITIVE_DIR}/aws/${name}"
      elif [[ -d "${K8S_PLAT_CLUSTER_INPUT_DIR}/openstack/${name}" ]]; then
        dest="${K8S_PLAT_SENSITIVE_DIR}/openstack/${name}"
      fi
      [[ -n "${dest}" && ! -e "${dest}" ]] || continue
      if [[ -f "${src}/terraform.tfstate" || -f "${src}/ssh.pem" || -f "${src}/kubeconfig" || -f "${src}/cluster.env" ]]; then
        mkdir -p "$(dirname "${dest}")"
        mv "${src}" "${dest}"
        echo "==> Moved ${src} -> ${dest}"
      fi
    done
  fi
}

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

k8s_plat_s3_offer() {
  "${REPO_ROOT}/scripts/sensitive/s3.sh" offer
}

# Required scalar from cluster YAML. Prints the value or errors.
k8s_plat_yaml_require() {
  local file="$1"
  local key="$2"
  local val=""
  if ! val="$(k8s_plat_yaml_get "${file}" "${key}")"; then
    echo "Missing ${key} in ${file}" >&2
    return 1
  fi
  printf '%s' "${val}"
}
