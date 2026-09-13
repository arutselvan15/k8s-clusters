output "project_id" {
  value = data.openstack_identity_auth_scope_v3.current.project_id
}

output "project_name" {
  value = data.openstack_identity_auth_scope_v3.current.project_name
}

output "user_name" {
  value = data.openstack_identity_auth_scope_v3.current.user_name
}

output "network_name" {
  value = var.network_name
}

output "network_id" {
  value = data.openstack_networking_network_v2.lab.id
}

output "security_group_id" {
  value = openstack_networking_secgroup_v2.lab.id
}

output "admin_cidr" {
  value = var.admin_cidr
}

output "ssh_user" {
  value = var.ssh_user
}

output "ssh_private_key_path" {
  value = local_file.ssh_private_key.filename
}

output "control_plane_public_ip" {
  value       = openstack_networking_port_v2.control_plane.all_fixed_ips[0]
  description = "Fixed IP on the existing tenant network (no floating IP)."
}

output "control_plane_private_ip" {
  value = openstack_compute_instance_v2.control_plane.access_ip_v4
}

output "ssh_control_plane" {
  value = "ssh -i ${local_file.ssh_private_key.filename} ${var.ssh_user}@${openstack_networking_port_v2.control_plane.all_fixed_ips[0]}"
}

output "worker_public_ip" {
  value       = try(openstack_networking_port_v2.worker[0].all_fixed_ips[0], "")
  description = "First worker fixed IP (empty if worker_nodes = 0)."
}

output "worker_public_ips" {
  value       = join(" ", [for p in openstack_networking_port_v2.worker : p.all_fixed_ips[0]])
  description = "All worker fixed IPs, space-separated (kubeadm inventory)."
}

output "ssh_worker" {
  value = try(
    "ssh -i ${local_file.ssh_private_key.filename} ${var.ssh_user}@${openstack_networking_port_v2.worker[0].all_fixed_ips[0]}",
    ""
  )
}

output "octavia_lb_count" {
  value = length(var.octavia_lbs)
}

output "octavia_lb_vips" {
  value       = { for k, lb in openstack_lb_loadbalancer_v2.this : k => lb.vip_address }
  description = "Map of Octavia VIP addresses keyed by octavia_lbs.name."
}

output "ingress_lb_vip" {
  value       = try(openstack_lb_loadbalancer_v2.this["ingress"].vip_address, "")
  description = "VIP for the LB named ingress, if present."
}
