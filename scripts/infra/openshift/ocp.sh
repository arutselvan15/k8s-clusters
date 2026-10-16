#!/usr/bin/env bash
# OpenShift on OpenStack, one phase at a time. Each phase is a small script
# under phases/ whose header explains what it does and why; ocp.sh prints that
# header, runs the phase, records it as done, and tells you what comes next.

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/infra/openshift/lib.sh
source "${REPO_ROOT}/scripts/infra/openshift/lib.sh"

PHASES=(
  00-preflight
  10-infra
  20-jumphost
  30-tools
  40-install-config
  50-manifests
  60-create
  70-bootstrap
  80-install
  90-verify
)

usage() {
  cat <<EOF
Usage: ./scripts/infra/openshift/ocp.sh [cluster] [command] [options]

Commands (default: next):
  next              run the next pending phase, then stop
  all [phase]       run every pending phase (optionally stop after [phase])
  <phase>           run one phase again, e.g. 50, 50-manifests or manifests
  status            show done / pending for every phase
  explain <phase>   print what a phase does without running it

Options:
  -y, --yes         terraform apply/destroy without the prompt (phase 10)
  -f, --force       run a phase even if an earlier phase is not done
  -h, --help

cluster is the id under clusters/openshift/ (optional when there is one).

Phases:
$(for p in "${PHASES[@]}"; do printf '  %-18s %s\n' "${p}" "$(phase_summary "${p}")"; done)

Teardown: ./scripts/infra/openshift/down.sh [cluster]
EOF
}

phase_file() {
  echo "${OCP_SCRIPT_DIR}/phases/$1.sh"
}

# Header = leading comment block after the shebang, '# ' stripped.
phase_header() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$(phase_file "$1")"
}

phase_summary() {
  phase_header "$1" | head -n 1
}

# Accepts 50, 50-manifests or manifests.
phase_resolve() {
  local want="$1" p
  for p in "${PHASES[@]}"; do
    if [[ "${p}" == "${want}" || "${p%%-*}" == "${want}" || "${p#*-}" == "${want}" ]]; then
      echo "${p}"
      return 0
    fi
  done
  echo "Unknown phase: ${want}. Known: ${PHASES[*]}" >&2
  return 1
}

phase_next() {
  local p
  for p in "${PHASES[@]}"; do
    if ! ocp_phase_done "${p}"; then
      echo "${p}"
      return 0
    fi
  done
  return 1
}

phase_status() {
  local p mark next
  next="$(phase_next || true)"
  echo "Cluster ${OCP_CLUSTER_NAME} (${K8S_PLAT_CLUSTER_CONFIG})"
  for p in "${PHASES[@]}"; do
    if ocp_phase_done "${p}"; then
      mark="done $(cat "${OCP_PHASE_DIR}/${p}.done")"
    elif [[ "${p}" == "${next}" ]]; then
      mark="NEXT"
    else
      mark="pending"
    fi
    printf '  %-18s %-28s %s\n' "${p}" "${mark}" "$(phase_summary "${p}")"
  done
}

phase_run() {
  local phase="$1" p
  if [[ "${FORCE}" != "true" ]]; then
    for p in "${PHASES[@]}"; do
      [[ "${p}" == "${phase}" ]] && break
      if ! ocp_phase_done "${p}"; then
        ocp_die "${phase} needs ${p} first (or pass --force)."
      fi
    done
  fi

  echo ""
  echo "################################################################"
  echo "# Phase ${phase}"
  echo "################################################################"
  phase_header "${phase}" | sed 's/^/  /'
  echo ""

  # Subshell: a phase that exits or fails cannot leave state behind here.
  (
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$(phase_file "${phase}")"
  )
  ocp_phase_mark "${phase}"
  echo ""
  echo "==> ${phase} done."

  case "${phase}" in
    10-infra | 90-verify) k8s_plat_s3_offer ;;
  esac
}

print_next() {
  local next
  if next="$(phase_next)"; then
    echo ""
    echo "Next: ${next} — $(phase_summary "${next}")"
    echo "  ./scripts/infra/openshift/ocp.sh ${OCP_CLUSTER_ID}            # run it"
    echo "  ./scripts/infra/openshift/ocp.sh ${OCP_CLUSTER_ID} explain ${next%%-*}  # read it first"
  else
    echo ""
    echo "All phases done."
  fi
}

CLUSTER=""
COMMAND=""
ARG=""
FORCE="false"
export OCP_AUTO_APPROVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      COMMAND="help"
      ;;
    -y | --yes)
      OCP_AUTO_APPROVE="-auto-approve"
      ;;
    -f | --force)
      FORCE="true"
      ;;
    next | all | status | explain)
      COMMAND="$1"
      if [[ "$1" == "all" || "$1" == "explain" ]] && [[ $# -gt 1 && "$2" != -* ]]; then
        ARG="$2"
        shift
      fi
      ;;
    *)
      if [[ -z "${CLUSTER}" && -d "${K8S_PLAT_CLUSTER_INPUT_DIR}/openshift/$1" ]]; then
        CLUSTER="$1"
      elif [[ -z "${COMMAND}" ]]; then
        COMMAND="phase"
        ARG="$1"
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ "${COMMAND}" == "help" ]]; then
  usage
  exit 0
fi

ocp_load_config "${CLUSTER}"

case "${COMMAND:-next}" in
  status)
    phase_status
    print_next
    ;;
  explain)
    phase="$(phase_resolve "${ARG:?explain needs a phase}")"
    echo "Phase ${phase}"
    phase_header "${phase}" | sed 's/^/  /'
    echo ""
    echo "Source: $(phase_file "${phase}")"
    ;;
  next)
    phase="$(phase_next)" || {
      echo "All phases done. Re-run one with: ocp.sh ${OCP_CLUSTER_ID} <phase>"
      exit 0
    }
    phase_run "${phase}"
    print_next
    ;;
  all)
    stop=""
    [[ -n "${ARG}" ]] && stop="$(phase_resolve "${ARG}")"
    while phase="$(phase_next)"; do
      phase_run "${phase}"
      [[ "${phase}" == "${stop}" ]] && break
    done
    print_next
    ;;
  phase)
    phase="$(phase_resolve "${ARG}")"
    phase_run "${phase}"
    print_next
    ;;
esac
