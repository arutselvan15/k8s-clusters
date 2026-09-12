variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type        = string
  default     = "default"
  description = "Profile name in k8s-platform/.aws/credentials."
}

variable "cluster_name" {
  type        = string
  default     = "k8s-aws"
  description = "Name prefix for AWS tags (from .aws/config)."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Private IPv4 range for the lab VPC."
}

variable "admin_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Who may SSH (22) and reach the Kubernetes API (6443). Lab default is open."
}

variable "node_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 size for control plane and workers."
}

variable "worker_nodes" {
  type        = number
  default     = 1
  description = "Worker EC2 count (>= 1). First worker is aws_instance.worker; extras are extra_workers."
}
