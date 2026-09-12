output "cluster_name" {
  value = module.cluster.cluster_name
}

output "kubernetes_version" {
  value = module.cluster.kubernetes_version
}

output "kubeconfig_path" {
  value = module.cluster.kubeconfig_path
}

output "endpoint" {
  value = module.cluster.endpoint
}
