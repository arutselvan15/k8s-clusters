# OpenStack lab: attach VMs to an existing Neutron network (no new net/router/FIP).
# Auth: clouds.yaml via OS_CLIENT_CONFIG_FILE (scripts/lib/os-env.sh).

# Step 1 — who we are (no extra cost).
data "openstack_identity_auth_scope_v3" "current" {
  name = "current"
}

data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "node" {
  name = var.node_flavor
}

# Existing tenant network (e.g. tenant-internal-direct-net). Looked up, not created.
data "openstack_networking_network_v2" "lab" {
  name = var.network_name
}

# Step 4 — security group: SSH, Kubernetes API, node-to-node.
resource "openstack_networking_secgroup_v2" "lab" {
  name        = "${var.cluster_name}-sg"
  description = "Lab: SSH, Kubernetes API, node-to-node"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_cidr
  security_group_id = openstack_networking_secgroup_v2.lab.id
}

resource "openstack_networking_secgroup_rule_v2" "kube_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.admin_cidr
  security_group_id = openstack_networking_secgroup_v2.lab.id
}

resource "openstack_networking_secgroup_rule_v2" "self" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.lab.id
  security_group_id = openstack_networking_secgroup_v2.lab.id
}

# Step 5 — SSH key + control-plane VM on the existing network.
resource "tls_private_key" "lab" {
  algorithm = "ED25519"
}

resource "openstack_compute_keypair_v2" "lab" {
  name       = "${var.cluster_name}-ssh"
  public_key = tls_private_key.lab.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.lab.private_key_openssh
  filename        = abspath(var.ssh_private_key_path)
  file_permission = "0600"
}

resource "openstack_networking_port_v2" "control_plane" {
  name               = "${var.cluster_name}-cp"
  network_id         = data.openstack_networking_network_v2.lab.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.lab.id]
}

resource "openstack_compute_instance_v2" "control_plane" {
  name      = "${var.cluster_name}-cp"
  flavor_id = data.openstack_compute_flavor_v2.node.id
  key_pair  = openstack_compute_keypair_v2.lab.name

  availability_zone = var.availability_zone != "" ? var.availability_zone : null

  block_device {
    uuid                  = data.openstack_images_image_v2.ubuntu.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.root_volume_gb
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.control_plane.id
  }

  metadata = {
    role = "control-plane"
  }
}

# Step 6 — worker VMs on the same existing network.
resource "openstack_networking_port_v2" "worker" {
  count              = var.worker_nodes
  name               = "${var.cluster_name}-wk-${count.index + 1}"
  network_id         = data.openstack_networking_network_v2.lab.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.lab.id]
}

resource "openstack_compute_instance_v2" "worker" {
  count     = var.worker_nodes
  name      = "${var.cluster_name}-wk-${count.index + 1}"
  flavor_id = data.openstack_compute_flavor_v2.node.id
  key_pair  = openstack_compute_keypair_v2.lab.name

  availability_zone = var.availability_zone != "" ? var.availability_zone : null

  block_device {
    uuid                  = data.openstack_images_image_v2.ubuntu.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.root_volume_gb
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.worker[count.index].id
  }

  metadata = {
    role = "worker"
  }
}
