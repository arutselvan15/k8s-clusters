#!/usr/bin/env bash
# Independent S3 backup of sensitive/ (credentials, tfstate, PEM, kubeconfig).
# Does not run Terraform or kubeadm. Cluster YAML stays in git under clusters/.
#
#   # set bucket in clusters/backup.yaml
#   ./scripts/sensitive/s3.sh init
#   ./scripts/sensitive/s3.sh push --prune
#   ./scripts/sensitive/s3.sh pull
#
# infra/up.sh, infra/down.sh, kubeadm/up.sh, and kubeadm/reset.sh call "offer".

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"

PRUNE=""

usage() {
  cat <<EOF
Usage: ./scripts/sensitive/s3.sh <init|push|pull|offer> [--prune]

  init    Create the S3 bucket (encryption, versioning, no public access)
  push    Upload sensitive/ to s3://<bucket>/<prefix>/
  pull    Download into sensitive/ (new laptop / crash recovery)
  offer   Prompt y/N, then push --prune (infra and kubeadm dispatchers)

  --prune  with push: delete S3 objects that are gone locally

Bucket name and region: clusters/backup.yaml (not a secret).
AWS keys: sensitive/aws/credentials if present, otherwise the usual AWS CLI chain.

Non-interactive: K8S_PLAT_S3_BACKUP=yes|no (skip the prompt).
EOF
}

k8s_plat_backup_aws_env() {
  if [[ -f "${K8S_PLAT_AWS_CREDENTIALS}" ]]; then
    export AWS_SHARED_CREDENTIALS_FILE="${K8S_PLAT_AWS_CREDENTIALS}"
  fi
  if [[ -f "${K8S_PLAT_AWS_CLI_CONF}" ]]; then
    export AWS_CONFIG_FILE="${K8S_PLAT_AWS_CLI_CONF}"
    export AWS_SDK_LOAD_CONFIG=1
  fi
}

k8s_plat_backup_load() {
  local file="${K8S_PLAT_BACKUP_YAML}"
  if [[ ! -f "${file}" ]]; then
    echo "Missing ${file}" >&2
    echo "Set bucket in ${file} (globally unique S3 name)." >&2
    return 1
  fi
  BACKUP_BUCKET="$(k8s_plat_yaml_get "${file}" bucket 2>/dev/null || true)"
  BACKUP_REGION="$(k8s_plat_yaml_get "${file}" region 2>/dev/null || echo "us-east-1")"
  BACKUP_PREFIX="$(k8s_plat_yaml_get "${file}" prefix 2>/dev/null || echo "k8s-platform/sensitive")"
  BACKUP_PREFIX="${BACKUP_PREFIX#/}"
  BACKUP_PREFIX="${BACKUP_PREFIX%/}"
  if [[ -z "${BACKUP_BUCKET}" || "${BACKUP_BUCKET}" == "REPLACE_ME" ]]; then
    echo "Set bucket in ${file} (globally unique S3 name)." >&2
    return 1
  fi
  if [[ ! "${BACKUP_BUCKET}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
    echo "Invalid S3 bucket name: ${BACKUP_BUCKET}" >&2
    return 1
  fi
}

k8s_plat_backup_uri() {
  echo "s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/"
}

cmd_init() {
  k8s_plat_backup_aws_env
  k8s_plat_backup_load
  "${REPO_ROOT}/scripts/lib/require-tools.sh" aws
  echo "==> Ensure bucket ${BACKUP_BUCKET} (${BACKUP_REGION})"
  if aws s3api head-bucket --bucket "${BACKUP_BUCKET}" 2>/dev/null; then
    echo "    bucket exists"
  else
    if [[ "${BACKUP_REGION}" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "${BACKUP_BUCKET}" --region "${BACKUP_REGION}"
    else
      aws s3api create-bucket --bucket "${BACKUP_BUCKET}" --region "${BACKUP_REGION}" \
        --create-bucket-configuration "LocationConstraint=${BACKUP_REGION}"
    fi
    echo "    created"
  fi
  aws s3api put-public-access-block --bucket "${BACKUP_BUCKET}" --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  aws s3api put-bucket-versioning --bucket "${BACKUP_BUCKET}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "${BACKUP_BUCKET}" --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
  echo "==> Bucket ready (private, versioned, AES-256). URI: $(k8s_plat_backup_uri)"
  echo "    Next: ./scripts/sensitive/s3.sh push --prune"
}

cmd_push() {
  k8s_plat_backup_aws_env
  k8s_plat_backup_load
  "${REPO_ROOT}/scripts/lib/require-tools.sh" aws
  mkdir -p "${K8S_PLAT_SENSITIVE_DIR}"
  local extra=()
  if [[ -n "${PRUNE}" ]]; then
    extra+=(--delete)
  fi
  echo "==> Push ${K8S_PLAT_SENSITIVE_DIR}/ -> $(k8s_plat_backup_uri)"
  aws s3 sync "${K8S_PLAT_SENSITIVE_DIR}/" "$(k8s_plat_backup_uri)" \
    --sse AES256 --region "${BACKUP_REGION}" "${extra[@]}"
  echo "==> Push complete. Object contents are not printed."
}

cmd_offer() {
  local reply=""

  k8s_plat_backup_aws_env
  if ! k8s_plat_backup_load 2>/dev/null; then
    echo "==> Skip S3 backup (set bucket in clusters/backup.yaml, then ./scripts/sensitive/s3.sh init)."
    return 0
  fi

  PRUNE=1
  echo ""
  echo "S3 backup: push ${K8S_PLAT_SENSITIVE_DIR}/ -> $(k8s_plat_backup_uri)"
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

cmd_pull() {
  k8s_plat_backup_aws_env
  k8s_plat_backup_load
  "${REPO_ROOT}/scripts/lib/require-tools.sh" aws
  mkdir -p "${K8S_PLAT_SENSITIVE_DIR}"
  echo "==> Pull $(k8s_plat_backup_uri) -> ${K8S_PLAT_SENSITIVE_DIR}/"
  aws s3 sync "$(k8s_plat_backup_uri)" "${K8S_PLAT_SENSITIVE_DIR}/" --region "${BACKUP_REGION}"
  local f
  while IFS= read -r -d '' f; do
    chmod 600 "${f}" || true
  done < <(find "${K8S_PLAT_SENSITIVE_DIR}" -type f \( \
    -name credentials -o -name clouds.yaml -o -name '*.pem' -o -name kubeconfig \
    -o -name cluster.env -o -name terraform.tfstate -o -name '*.tfstate*' \
    \) -print0 2>/dev/null)
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
