resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = "kindest/node:v${var.kubernetes_version}"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    dynamic "node" {
      for_each = range(var.control_plane_nodes)
      content {
        role = "control-plane"

        dynamic "extra_port_mappings" {
          for_each = node.key == 0 ? var.extra_port_mappings : []
          content {
            container_port = extra_port_mappings.value.container_port
            host_port      = extra_port_mappings.value.host_port
            protocol       = extra_port_mappings.value.protocol
          }
        }
      }
    }

    dynamic "node" {
      for_each = range(var.worker_nodes)
      content {
        role = "worker"
      }
    }
  }
}

resource "local_file" "kubeconfig" {
  content         = kind_cluster.this.kubeconfig
  filename        = var.kubeconfig_path
  file_permission = "0600"
}
