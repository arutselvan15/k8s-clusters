#!/usr/bin/env bash
# Tools: openshift-install + oc for the pinned release, checksum-verified.
#
# Runs on: jump host (remote/30-tools.sh).
#
# Why: the installer binary IS the release. openshift-install 4.22.17 embeds
# the release image digest (quay.io/openshift-release-dev/ocp-release@sha256)
# and the RHCOS image URLs, so installing a different z-stream means
# downloading a different installer, not changing a flag.
#
# Does:
#   - downloads openshift-install-linux-<release>.tar.gz and
#     openshift-client-linux-<release>.tar.gz from mirror.openshift.com
#   - verifies both against that release's sha256sum.txt
#   - installs openshift-install, oc, kubectl into /usr/local/bin
#   - prints the release image and the RHCOS OpenStack artifact
#
# Learn: openshift-install version; openshift-install coreos print-stream-json

ocp_load_outputs
ocp_remote 30-tools.sh
