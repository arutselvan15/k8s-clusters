#!/usr/bin/env bash
# Create: start `openshift-install create cluster` in the background.
#
# Runs on: jump host (remote/60-create.sh). Returns once the installer is
# past validation; the install keeps running if your SSH session drops.
#
# Why: create cluster takes 45-90 minutes. Instead of one blocking call it is
# split into start (this phase), bootstrap (70) and install (80), so you can
# stop between them and look around.
#
# What the installer does now, in order:
#   1. validates install-config against OpenStack (quota, flavors, network)
#   2. downloads RHCOS and uploads it to Glance as <infra-id>-rhcos
#   3. creates security groups, VIP ports (attaching your 2 FIPs),
#      server groups, then the bootstrap and master VMs (Cluster API)
#   4. bootstrap node serves ignition and a temporary control plane; masters
#      boot, pull the release image, form etcd, and apply install/manifests
#      (Cilium included) -> phase 70 waits for this
#   5. bootstrap VM is deleted; operators bring up workers, ingress, console
#      -> phase 80 waits for this
#
# Watch it: ssh -i sensitive/openshift/<cluster>/ssh.pem ubuntu@<jump FIP>
#           tail -f ~/ocp/<cluster>/create.log
# Learn: install/.openshift_install.log has debug-level detail.

ocp_load_outputs
ocp_remote 60-create.sh
