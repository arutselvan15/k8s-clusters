module "cluster" {
  source = "../../modules/cluster-kind"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  control_plane_nodes = var.control_plane_nodes
  worker_nodes        = var.worker_nodes
  kubeconfig_path     = var.kubeconfig_path

  extra_port_mappings = [
    { container_port = 80, host_port = var.http_host_port, protocol = "TCP" },
    { container_port = 443, host_port = var.https_host_port, protocol = "TCP" },
  ]
}
