# Optional Octavia LBs (one VIP each: TCP 80 + 443 → NodePorts). Length of octavia_lbs is N.
# OpenStack load-balancer quota still caps how many can exist in the project.
# Pin NodePorts in k8s-apps. Do not also create these LBs via OCCM / Helm LoadBalancer.

locals {
  octavia_lbs = { for lb in var.octavia_lbs : lb.name => lb }
  octavia_n   = length(local.octavia_lbs) > 0 ? 1 : 0

  octavia_node_ips = concat(
    [openstack_networking_port_v2.control_plane.all_fixed_ips[0]],
    [for p in openstack_networking_port_v2.worker : p.all_fixed_ips[0]]
  )
  octavia_vip_subnet_id = local.octavia_n == 1 ? data.openstack_networking_subnet_v2.octavia[0].id : ""

  octavia_listeners = merge([
    for name, lb in local.octavia_lbs : {
      "${name}-http" = {
        lb_name       = name
        protocol_port = 80
        node_port     = lb.http_node_port
      }
      "${name}-https" = {
        lb_name       = name
        protocol_port = 443
        node_port     = lb.https_node_port
      }
    }
  ]...)

  octavia_members = merge([
    for lkey, lis in local.octavia_listeners : {
      for ip in local.octavia_node_ips :
      "${lkey}-${ip}" => {
        listener_key = lkey
        address      = ip
        node_port    = lis.node_port
      }
    }
  ]...)

  octavia_node_ports = toset(flatten([
    for lb in values(local.octavia_lbs) : [
      tostring(lb.http_node_port),
      tostring(lb.https_node_port),
    ]
  ]))
}

data "openstack_lb_flavor_v2" "octavia" {
  count = local.octavia_n == 1 && var.octavia_lb_flavor != "" ? 1 : 0
  name  = var.octavia_lb_flavor
}

data "openstack_networking_subnet_v2" "octavia" {
  count      = local.octavia_n
  name       = var.subnet_name
  network_id = data.openstack_networking_network_v2.lab.id
}

resource "openstack_networking_secgroup_rule_v2" "octavia_nodeport" {
  for_each          = local.octavia_node_ports
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.value)
  port_range_max    = tonumber(each.value)
  remote_ip_prefix  = data.openstack_networking_subnet_v2.octavia[0].cidr
  security_group_id = openstack_networking_secgroup_v2.lab.id
}

resource "openstack_lb_loadbalancer_v2" "this" {
  for_each      = local.octavia_lbs
  name          = "${var.cluster_name}-${each.key}"
  vip_subnet_id = local.octavia_vip_subnet_id
  flavor_id     = try(data.openstack_lb_flavor_v2.octavia[0].id, null)

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

resource "openstack_lb_listener_v2" "this" {
  for_each        = local.octavia_listeners
  name            = "${var.cluster_name}-${each.key}"
  protocol        = "TCP"
  protocol_port   = each.value.protocol_port
  loadbalancer_id = openstack_lb_loadbalancer_v2.this[each.value.lb_name].id
}

resource "openstack_lb_pool_v2" "this" {
  for_each    = local.octavia_listeners
  name        = "${var.cluster_name}-${each.key}"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.this[each.key].id
}

resource "openstack_lb_monitor_v2" "this" {
  for_each    = local.octavia_listeners
  pool_id     = openstack_lb_pool_v2.this[each.key].id
  type        = "TCP"
  delay       = 10
  timeout     = 5
  max_retries = 3
}

resource "openstack_lb_member_v2" "this" {
  for_each      = local.octavia_members
  pool_id       = openstack_lb_pool_v2.this[each.value.listener_key].id
  subnet_id     = local.octavia_vip_subnet_id
  address       = each.value.address
  protocol_port = each.value.node_port
}
