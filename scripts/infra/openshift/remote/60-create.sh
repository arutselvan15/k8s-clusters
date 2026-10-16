#!/usr/bin/env bash
# Phase 60 on the jump host. Env: OCP_WORK, OCP_INSTALL
# create.pid / create.rc / create.log under OCP_WORK let phases 70 and 80
# (and you) tell running, finished and failed apart.

set -euo pipefail

log="${OCP_WORK}/create.log"
pidf="${OCP_WORK}/create.pid"
rcf="${OCP_WORK}/create.rc"

if [[ -f "${pidf}" ]] && kill -0 "$(cat "${pidf}")" 2>/dev/null; then
  echo "    openshift-install create cluster already running (pid $(cat "${pidf}")); tail -f ${log}"
  exit 0
fi
if [[ -f "${OCP_INSTALL}/metadata.json" ]]; then
  if [[ "$(cat "${rcf}" 2>/dev/null)" == "0" ]]; then
    echo "    cluster already created (create.rc=0)."
    exit 0
  fi
  echo "A previous create stopped (create.rc=$(cat "${rcf}" 2>/dev/null || echo '?')). Last lines of ${log}:" >&2
  tail -n 20 "${log}" >&2 || true
  echo "Re-running wait phases is fine; to start over: down.sh <cluster> cluster, then phases 40-60." >&2
  exit 1
fi
if [[ ! -d "${OCP_INSTALL}/manifests" ]]; then
  echo "No ${OCP_INSTALL}/manifests - run phase 50 first." >&2
  exit 1
fi

rm -f "${rcf}"
echo "==> starting openshift-install create cluster (log ${log})"
setsid nohup bash -c "openshift-install create cluster --dir '${OCP_INSTALL}' --log-level info; echo \$? > '${rcf}'" \
  >"${log}" 2>&1 </dev/null &
echo $! >"${pidf}"

# Wait until it is clearly past validation, or has failed.
for _ in $(seq 1 90); do
  sleep 10
  if [[ -f "${rcf}" ]]; then
    echo "openshift-install exited early (rc $(cat "${rcf}")):" >&2
    tail -n 30 "${log}" >&2
    exit 1
  fi
  if grep -qE 'Creating infrastructure resources|Waiting up to' "${log}"; then
    break
  fi
done
tail -n 15 "${log}" | sed 's/^/    /'
echo ""
echo "    still running in the background (pid $(cat "${pidf}"))."
