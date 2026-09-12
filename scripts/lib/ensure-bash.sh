#!/bin/sh
# POSIX-only. Re-exec with Bash when the caller used `sh script`
# (macOS /bin/sh is bash --posix; process substitution and some arrays break).
#
# Copy the three lines below to the top of a CLI, or:
#   . "${REPO_ROOT}/scripts/lib/ensure-bash.sh"
# after REPO_ROOT is set. Sourced libraries must not call this (it execs $0).
#
# Linux /bin/sh is often dash and cannot parse Bash arrays in the same file,
# so the guard never runs there — use ./scripts/... or bash scripts/...

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
