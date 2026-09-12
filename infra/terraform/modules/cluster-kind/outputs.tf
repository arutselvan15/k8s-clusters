output "cluster_name" {
  value = kind_cluster.this.name
}

output "kubernetes_version" {
  value = var.kubernetes_version
}

output "kubeconfig_path" {
  value = local_file.kubeconfig.filename
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}
