#!/usr/bin/env bash
# 8c — kubeadm join on the worker. Streamed over SSH stdin; not copied.
# Env: JOIN_CMD (full `kubeadm join ...` line). Do not echo it (bootstrap token).

set -euo pipefail

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo "    already joined; skipping kubeadm join"
  exit 0
fi

: "${JOIN_CMD:?JOIN_CMD must be the kubeadm join command}"
if [[ "${JOIN_CMD}" != kubeadm\ join* ]]; then
  echo "JOIN_CMD is not a kubeadm join command" >&2
  exit 1
fi

sudo bash -c "${JOIN_CMD}"
