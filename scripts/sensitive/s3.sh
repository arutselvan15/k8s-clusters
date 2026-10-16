#!/usr/bin/env bash
# Independent S3 backup of sensitive/ (credentials, tfstate, PEM, kubeconfig).
# Does not run Terraform or kubeadm. Cluster YAML stays in git under clusters/.
#
#   # same fields per target in clusters/backup.yaml; switch with default or --target
#   ./scripts/sensitive/s3.sh init
#   ./scripts/sensitive/s3.sh push --prune
#   ./scripts/sensitive/s3.sh pull --target <target>
#
# infra/up.sh, infra/down.sh, kubeadm/up.sh, and kubeadm/reset.sh call "offer".
#
# `sh script` on macOS is bash --posix; re-exec so the rest of this file runs.

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"

PRUNE=""
BACKUP_CONFIG_FILE=""

usage() {
  cat <<EOF
Usage: ./scripts/sensitive/s3.sh <init|push|pull|offer> [--target <name>] [--prune]

  init    Create the bucket. AWS targets also get block-public, versioning, SSE.
  push    Upload sensitive/ to the selected target
  pull    Download the selected target into sensitive/ (new laptop / crash recovery)
  offer   Prompt y/N, then push --prune (infra and kubeadm dispatchers)

  --prune  with push: delete remote objects that are gone locally
  --target Select a target from clusters/backup.yaml.

Target selection: --target, then K8S_PLAT_S3_TARGET, then backup.yaml default.
Each target has the same fields (bucket, region, prefix, endpoint, profile,
credentials, addressing, sse). Keys stay in the credentials file, not in YAML.

Non-interactive: K8S_PLAT_S3_BACKUP=yes|no (skip the prompt).
EOF
}

k8s_plat_backup_cleanup() {
  if [[ -n "${BACKUP_CONFIG_FILE}" && -f "${BACKUP_CONFIG_FILE}" ]]; then
    rm -f "${BACKUP_CONFIG_FILE}"
  fi
  BACKUP_CONFIG_FILE=""
}

trap k8s_plat_backup_cleanup EXIT

k8s_plat_backup_field() {
  local file="$1"
  local dotted="$2"
  k8s_plat_yaml_get "${file}" "${dotted}" 2>/dev/null || true
}

k8s_plat_backup_load() {
  local file="${K8S_PLAT_BACKUP_YAML}"
  local configured_default=""
  local target_prefix=""
  local sse_raw=""
  if [[ ! -f "${file}" ]]; then
    echo "Missing ${file}" >&2
    echo "Configure a backup target in ${file}." >&2
    return 1
  fi

  configured_default="$(k8s_plat_backup_field "${file}" default)"
  BACKUP_TARGET="${BACKUP_TARGET_REQUESTED:-${K8S_PLAT_S3_TARGET:-${configured_default}}}"
  if [[ -n "${BACKUP_TARGET}" ]]; then
    if [[ ! "${BACKUP_TARGET}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]]; then
      echo "Invalid backup target name: ${BACKUP_TARGET}" >&2
      return 1
    fi
    target_prefix="targets.${BACKUP_TARGET}"
  else
    BACKUP_TARGET="default"
    target_prefix=""
  fi

  if [[ -n "${target_prefix}" ]]; then
    BACKUP_BUCKET="$(k8s_plat_backup_field "${file}" "${target_prefix}.bucket")"
    BACKUP_REGION="$(k8s_plat_backup_field "${file}" "${target_prefix}.region")"
    BACKUP_PREFIX="$(k8s_plat_backup_field "${file}" "${target_prefix}.prefix")"
    BACKUP_ENDPOINT="$(k8s_plat_backup_field "${file}" "${target_prefix}.endpoint")"
    BACKUP_PROFILE="$(k8s_plat_backup_field "${file}" "${target_prefix}.profile")"
    BACKUP_CREDENTIALS="$(k8s_plat_backup_field "${file}" "${target_prefix}.credentials")"
    BACKUP_ADDRESSING="$(k8s_plat_backup_field "${file}" "${target_prefix}.addressing")"
    sse_raw="$(k8s_plat_backup_field "${file}" "${target_prefix}.sse")"
  else
    BACKUP_BUCKET="$(k8s_plat_backup_field "${file}" bucket)"
    BACKUP_REGION="$(k8s_plat_backup_field "${file}" region)"
    BACKUP_PREFIX="$(k8s_plat_backup_field "${file}" prefix)"
    BACKUP_ENDPOINT="$(k8s_plat_backup_field "${file}" endpoint)"
    BACKUP_PROFILE="$(k8s_plat_backup_field "${file}" profile)"
    BACKUP_CREDENTIALS="$(k8s_plat_backup_field "${file}" credentials)"
    BACKUP_ADDRESSING="$(k8s_plat_backup_field "${file}" addressing)"
    sse_raw="$(k8s_plat_backup_field "${file}" sse)"
  fi

  [[ -n "${BACKUP_REGION}" ]] || BACKUP_REGION="us-east-1"
  [[ -n "${BACKUP_PREFIX}" ]] || BACKUP_PREFIX="k8s-platform/sensitive"
  [[ -n "${BACKUP_PROFILE}" ]] || BACKUP_PROFILE="default"
  if [[ -z "${BACKUP_ADDRESSING}" ]]; then
    if [[ -n "${BACKUP_ENDPOINT}" ]]; then
      BACKUP_ADDRESSING="path"
    else
      BACKUP_ADDRESSING="virtual"
    fi
  fi
  if [[ -z "${sse_raw}" ]]; then
    if [[ -n "${target_prefix}" ]] && ! k8s_plat_yaml_get "${file}" "${target_prefix}.sse" >/dev/null 2>&1; then
      sse_raw="AES256"
    elif [[ -z "${target_prefix}" ]] && ! k8s_plat_yaml_get "${file}" sse >/dev/null 2>&1; then
      sse_raw="AES256"
    else
      sse_raw="none"
    fi
  fi
  BACKUP_PREFIX="${BACKUP_PREFIX#/}"
  BACKUP_PREFIX="${BACKUP_PREFIX%/}"

  if [[ -z "${BACKUP_BUCKET}" || "${BACKUP_BUCKET}" == "REPLACE_ME" ]]; then
    echo "Set bucket for target '${BACKUP_TARGET}' in ${file}." >&2
    return 1
  fi
  if [[ ! "${BACKUP_BUCKET}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
    echo "Invalid S3 bucket name: ${BACKUP_BUCKET}" >&2
    return 1
  fi
  if [[ ! "${BACKUP_REGION}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
    echo "Invalid region for target '${BACKUP_TARGET}': ${BACKUP_REGION}" >&2
    return 1
  fi
  if [[ -n "${BACKUP_PREFIX}" && ! "${BACKUP_PREFIX}" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,200}$ ]]; then
    echo "Invalid prefix for target '${BACKUP_TARGET}'." >&2
    return 1
  fi
  if [[ -n "${BACKUP_ENDPOINT}" && ! "${BACKUP_ENDPOINT}" =~ ^https://[^[:space:]@]+$ ]]; then
    echo "endpoint for target '${BACKUP_TARGET}' must be an https URL with no embedded credentials." >&2
    return 1
  fi
  if [[ ! "${BACKUP_PROFILE}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; then
    echo "Invalid profile for target '${BACKUP_TARGET}': ${BACKUP_PROFILE}" >&2
    return 1
  fi
  if [[ ! "${BACKUP_ADDRESSING}" =~ ^(auto|virtual|path)$ ]]; then
    echo "addressing for target '${BACKUP_TARGET}' must be auto, virtual, or path." >&2
    return 1
  fi
  case "${sse_raw}" in
    AES256 | aws:kms)
      BACKUP_SSE="${sse_raw}"
      ;;
    none)
      BACKUP_SSE=""
      ;;
    *)
      echo "sse for target '${BACKUP_TARGET}' must be AES256, aws:kms, or none." >&2
      return 1
      ;;
  esac

  BACKUP_CREDENTIALS_FILE=""
  if [[ -n "${BACKUP_ENDPOINT}" && -z "${BACKUP_CREDENTIALS}" ]]; then
    echo "Target '${BACKUP_TARGET}' has an endpoint, so it must set credentials." >&2
    return 1
  fi
  if [[ -z "${BACKUP_CREDENTIALS}" && -z "${BACKUP_ENDPOINT}" && -f "${K8S_PLAT_AWS_CREDENTIALS}" ]]; then
    BACKUP_CREDENTIALS="sensitive/aws/s3.credentials"
  fi
  if [[ -n "${BACKUP_CREDENTIALS}" ]]; then
    if [[ "${BACKUP_CREDENTIALS}" == /* || "${BACKUP_CREDENTIALS}" == *".."* ]]; then
      echo "credentials for target '${BACKUP_TARGET}' must be a relative path under sensitive/." >&2
      return 1
    fi
    case "${BACKUP_CREDENTIALS}" in
      sensitive/*) ;;
      *)
        echo "credentials for target '${BACKUP_TARGET}' must be under sensitive/." >&2
        return 1
        ;;
    esac
    BACKUP_CREDENTIALS_FILE="${REPO_ROOT}/${BACKUP_CREDENTIALS}"
    if [[ ! -f "${BACKUP_CREDENTIALS_FILE}" ]]; then
      echo "Missing ${BACKUP_CREDENTIALS} for target '${BACKUP_TARGET}'." >&2
      echo "Copy the matching *.example and fill profile '${BACKUP_PROFILE}'. Do not commit it." >&2
      return 1
    fi
    if ! k8s_plat_ini_get "${BACKUP_CREDENTIALS_FILE}" aws_access_key_id "${BACKUP_PROFILE}" >/dev/null; then
      echo "Profile '${BACKUP_PROFILE}' in ${BACKUP_CREDENTIALS} is missing aws_access_key_id." >&2
      return 1
    fi
    if ! k8s_plat_ini_get "${BACKUP_CREDENTIALS_FILE}" aws_secret_access_key "${BACKUP_PROFILE}" >/dev/null; then
      echo "Profile '${BACKUP_PROFILE}' in ${BACKUP_CREDENTIALS} is missing aws_secret_access_key." >&2
      return 1
    fi
  fi
}

k8s_plat_backup_apply_env() {
  local header="[default]"
  k8s_plat_backup_cleanup
  BACKUP_CONFIG_FILE="$(mktemp "${TMPDIR:-/tmp}/k8s-plat-s3.XXXXXX")"
  chmod 600 "${BACKUP_CONFIG_FILE}"
  if [[ "${BACKUP_PROFILE}" != "default" ]]; then
    header="[profile ${BACKUP_PROFILE}]"
  fi
  cat > "${BACKUP_CONFIG_FILE}" <<EOF
${header}
region = ${BACKUP_REGION}
output = json
s3 =
    addressing_style = ${BACKUP_ADDRESSING}
EOF
  export AWS_CONFIG_FILE="${BACKUP_CONFIG_FILE}"
  export AWS_SDK_LOAD_CONFIG=1
  export AWS_PROFILE="${BACKUP_PROFILE}"
  if [[ -n "${BACKUP_CREDENTIALS_FILE}" ]]; then
    export AWS_SHARED_CREDENTIALS_FILE="${BACKUP_CREDENTIALS_FILE}"
  fi
}

k8s_plat_backup_prepare() {
  k8s_plat_backup_load
  k8s_plat_backup_apply_env
}

k8s_plat_backup_uri() {
  echo "s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/"
}

k8s_plat_backup_describe() {
  if [[ -n "${BACKUP_ENDPOINT}" ]]; then
    echo "target '${BACKUP_TARGET}' ($(k8s_plat_backup_uri)) endpoint ${BACKUP_ENDPOINT}"
  else
    echo "target '${BACKUP_TARGET}' ($(k8s_plat_backup_uri))"
  fi
}

k8s_plat_aws() {
  if [[ -n "${BACKUP_ENDPOINT}" ]]; then
    aws --endpoint-url "${BACKUP_ENDPOINT}" "$@"
  else
    aws "$@"
  fi
}

k8s_plat_s3_sync() {
  local src="$1"
  local dst="$2"
  if [[ -n "${PRUNE}" && -n "${BACKUP_SSE}" ]]; then
    k8s_plat_aws s3 sync "${src}" "${dst}" --region "${BACKUP_REGION}" --sse "${BACKUP_SSE}" --delete
  elif [[ -n "${PRUNE}" ]]; then
    k8s_plat_aws s3 sync "${src}" "${dst}" --region "${BACKUP_REGION}" --delete
  elif [[ -n "${BACKUP_SSE}" ]]; then
    k8s_plat_aws s3 sync "${src}" "${dst}" --region "${BACKUP_REGION}" --sse "${BACKUP_SSE}"
  else
    k8s_plat_aws s3 sync "${src}" "${dst}" --region "${BACKUP_REGION}"
  fi
}

cmd_init() {
  k8s_plat_backup_prepare
  "${REPO_ROOT}/scripts/lib/require-tools.sh" aws
  echo "==> Ensure $(k8s_plat_backup_describe)"
  if k8s_plat_aws s3api head-bucket --bucket "${BACKUP_BUCKET}" --region "${BACKUP_REGION}" 2>/dev/null; then
    echo "    bucket exists"
  else
    # us-east-1 and region-specific custom endpoints (OpenStack COS) reject
    # LocationConstraint. Other AWS regions require it.
    if [[ -n "${BACKUP_ENDPOINT}" || "${BACKUP_REGION}" == "us-east-1" ]]; then
      k8s_plat_aws s3api create-bucket --bucket "${BACKUP_BUCKET}" --region "${BACKUP_REGION}"
    else
      k8s_plat_aws s3api create-bucket --bucket "${BACKUP_BUCKET}" --region "${BACKUP_REGION}" \
        --create-bucket-configuration "LocationConstraint=${BACKUP_REGION}"
    fi
    echo "    created"
  fi
  if [[ -z "${BACKUP_ENDPOINT}" ]]; then
    k8s_plat_aws s3api put-public-access-block --bucket "${BACKUP_BUCKET}" --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    k8s_plat_aws s3api put-bucket-versioning --bucket "${BACKUP_BUCKET}" \
      --versioning-configuration Status=Enabled
    k8s_plat_aws s3api put-bucket-encryption --bucket "${BACKUP_BUCKET}" --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
    echo "==> Bucket ready (private, versioned, AES-256). URI: $(k8s_plat_backup_uri)"
  else
    echo "==> Bucket ready at the custom endpoint. URI: $(k8s_plat_backup_uri)"
    echo "    Keep this container private. AWS public-access block, versioning, and bucket encryption were not applied."
  fi
  echo "    Next: ./scripts/sensitive/s3.sh push --prune"
}

cmd_push() {
  k8s_plat_backup_prepare
  "${REPO_ROOT}/scripts/lib/require-tools.sh" aws
  mkdir -p "${K8S_PLAT_SENSITIVE_DIR}"
  echo "==> Push ${K8S_PLAT_SENSITIVE_DIR}/ -> $(k8s_plat_backup_describe)"
  k8s_plat_s3_sync "${K8S_PLAT_SENSITIVE_DIR}/" "$(k8s_plat_backup_uri)"
  echo "==> Push complete. Object contents are not printed."
}

cmd_offer() {
  local reply=""

  if ! k8s_plat_backup_prepare; then
    echo "==> Skip S3 backup (check clusters/backup.yaml, then run ./scripts/sensitive/s3.sh init)."
    return 0
  fi

  PRUNE=1
  echo ""
  echo "S3 backup: push ${K8S_PLAT_SENSITIVE_DIR}/ -> $(k8s_plat_backup_describe)"
  echo "  with prune (delete remote objects that are gone locally)"

  case "${K8S_PLAT_S3_BACKUP:-}" in
    1 | yes | YES | true | TRUE)
      cmd_push
      return 0
      ;;
    0 | no | NO | false | FALSE)
      echo "Skipped S3 backup (K8S_PLAT_S3_BACKUP=${K8S_PLAT_S3_BACKUP})."
      return 0
      ;;
  esac

  if [[ ! -t 0 ]]; then
    echo "Skipped S3 backup (stdin is not a TTY). Run: ./scripts/sensitive/s3.sh push --prune"
    return 0
  fi

  reply=""
  read -r -p "Push to S3 with prune? [y/N] " reply || true
  case "${reply}" in
    y | Y | yes | YES)
      cmd_push
      ;;
    *)
      echo "Skipped S3 backup."
      ;;
  esac
}

k8s_plat_backup_lock_down() {
  local f
  find "${K8S_PLAT_SENSITIVE_DIR}" -type f \( \
    -name credentials -o -name 's3.credentials' -o -name clouds.yaml -o -name '*.pem' -o -name kubeconfig \
    -o -name cluster.env -o -name terraform.tfstate -o -name '*.tfstate*' \
    \) -print0 2>/dev/null | while IFS= read -r -d '' f; do
    chmod 600 "${f}" || true
  done
}

cmd_pull() {
  k8s_plat_backup_prepare
  "${REPO_ROOT}/scripts/lib/require-tools.sh" aws
  mkdir -p "${K8S_PLAT_SENSITIVE_DIR}"
  echo "==> Pull $(k8s_plat_backup_describe) -> ${K8S_PLAT_SENSITIVE_DIR}/"
  k8s_plat_s3_sync "$(k8s_plat_backup_uri)" "${K8S_PLAT_SENSITIVE_DIR}/"
  k8s_plat_backup_lock_down
  echo "==> Pull complete. chmod 600 applied to keys, kubeconfig, and state."
}

CMD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --prune)
      PRUNE=1
      ;;
    -t | --target)
      shift
      if [[ $# -eq 0 || -z "$1" ]]; then
        echo "$0 requires a target name" >&2
        usage >&2
        exit 1
      fi
      BACKUP_TARGET_REQUESTED="$1"
      ;;
    init | push | pull | offer)
      CMD="$1"
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${CMD}" ]]; then
  usage >&2
  exit 1
fi

"cmd_${CMD}"
