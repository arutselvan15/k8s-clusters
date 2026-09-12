module "cluster" {
  source = "../../modules/cluster-kind"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  control_plane_nodes = var.control_plane_nodes
  worker_nodes        = var.worker_nodes
  kubeconfig_path     = abspath("${path.root}/../../../../sensitive/kind/kubeconfig")

  extra_port_mappings = [
    { container_port = 80, host_port = 8080, protocol = "TCP" },
    { container_port = 443, host_port = 8443, protocol = "TCP" },
  ]
}
